/* =====================================================================
   FSMVU Kampus Sosyal Agi - Veritabani Semasi (SQL Server / SSMS 21)
   Teknik Iletisim ve Proje Raporlama Dersi
   Calistirma: SSMS'te yeni bir sorgu penceresi acip tamamini F5 ile calistirin.
   ===================================================================== */

IF DB_ID(N'FSMVU_CampusNet') IS NULL
    CREATE DATABASE FSMVU_CampusNet;
GO

USE FSMVU_CampusNet;
GO

/* ---------------------------------------------------------------------
   Temizlik: tablolar varsa bagimlilik sirasina gore silinir
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.notifications;
DROP TABLE IF EXISTS dbo.event_attendees;
DROP TABLE IF EXISTS dbo.events;
DROP TABLE IF EXISTS dbo.comments;
DROP TABLE IF EXISTS dbo.post_likes;
DROP TABLE IF EXISTS dbo.post_media;
DROP TABLE IF EXISTS dbo.posts;
DROP TABLE IF EXISTS dbo.project_applications;
DROP TABLE IF EXISTS dbo.project_required_skills;
DROP TABLE IF EXISTS dbo.project_members;
DROP TABLE IF EXISTS dbo.projects;
DROP TABLE IF EXISTS dbo.club_members;
DROP TABLE IF EXISTS dbo.clubs;
DROP TABLE IF EXISTS dbo.follows;
DROP TABLE IF EXISTS dbo.user_skills;
DROP TABLE IF EXISTS dbo.skills;
DROP TABLE IF EXISTS dbo.profiles;
DROP TABLE IF EXISTS dbo.email_verifications;
DROP TABLE IF EXISTS dbo.users;
DROP TABLE IF EXISTS dbo.departments;
GO

/* ---------------------------------------------------------------------
   1. Bolumler
   --------------------------------------------------------------------- */
CREATE TABLE dbo.departments (
    department_id INT IDENTITY(1,1) CONSTRAINT PK_departments PRIMARY KEY,
    name          NVARCHAR(150) NOT NULL CONSTRAINT UQ_departments_name UNIQUE,
    faculty       NVARCHAR(150) NULL
);
GO

/* ---------------------------------------------------------------------
   2. Kullanicilar (ogrenci, akademisyen, kulup yoneticisi, mezun, admin)
      degree: on_lisans | lisans | yuksek_lisans | doktora
   --------------------------------------------------------------------- */
CREATE TABLE dbo.users (
    user_id           INT IDENTITY(1,1) CONSTRAINT PK_users PRIMARY KEY,
    student_no        VARCHAR(20)   NULL,
    email             NVARCHAR(150) NOT NULL CONSTRAINT UQ_users_email UNIQUE,
    password_hash     VARCHAR(255)  NOT NULL,
    first_name        NVARCHAR(60)  NOT NULL,
    last_name         NVARCHAR(60)  NOT NULL,
    role              VARCHAR(20)   NOT NULL CONSTRAINT DF_users_role DEFAULT 'student',
    department_id     INT           NULL,
    degree            VARCHAR(20)   NULL,
    class_year        TINYINT       NULL,
    graduation_year   SMALLINT      NULL,
    is_email_verified BIT           NOT NULL CONSTRAINT DF_users_verified DEFAULT 0,
    is_active         BIT           NOT NULL CONSTRAINT DF_users_active DEFAULT 1,
    created_at        DATETIME2(0)  NOT NULL CONSTRAINT DF_users_created DEFAULT SYSDATETIME(),
    last_login_at     DATETIME2(0)  NULL,

    CONSTRAINT FK_users_department FOREIGN KEY (department_id)
        REFERENCES dbo.departments(department_id) ON DELETE SET NULL,
    CONSTRAINT CK_users_role CHECK (role IN ('student','academic','club_admin','alumni','admin')),
    CONSTRAINT CK_users_degree CHECK (degree IS NULL OR degree IN ('on_lisans','lisans','yuksek_lisans','doktora')),
    CONSTRAINT CK_users_class_year CHECK (class_year IS NULL OR class_year BETWEEN 1 AND 8),
    -- Ogrenci ve mezunlar icin kurumsal e-posta zorunlulugu
    CONSTRAINT CK_users_student_email CHECK (
        role NOT IN ('student','alumni') OR email LIKE '%@stu.fsm.edu.tr'
    )
);
GO
-- Birden fazla NULL'a izin veren benzersiz ogrenci numarasi
CREATE UNIQUE INDEX UX_users_student_no ON dbo.users(student_no) WHERE student_no IS NOT NULL;
CREATE INDEX IX_users_department ON dbo.users(department_id);
CREATE INDEX IX_users_role ON dbo.users(role);
GO

/* ---------------------------------------------------------------------
   3. E-posta dogrulama kodlari
   --------------------------------------------------------------------- */
CREATE TABLE dbo.email_verifications (
    verification_id INT IDENTITY(1,1) CONSTRAINT PK_email_verifications PRIMARY KEY,
    user_id         INT          NOT NULL,
    token           VARCHAR(100) NOT NULL CONSTRAINT UQ_email_verifications_token UNIQUE,
    expires_at      DATETIME2(0) NOT NULL,
    used_at         DATETIME2(0) NULL,
    CONSTRAINT FK_emailver_user FOREIGN KEY (user_id)
        REFERENCES dbo.users(user_id) ON DELETE CASCADE
);
GO

/* ---------------------------------------------------------------------
   4. Profil / portfolyo (users ile 1:1)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.profiles (
    user_id         INT CONSTRAINT PK_profiles PRIMARY KEY,
    bio             NVARCHAR(MAX) NULL,
    avatar_url      VARCHAR(500)  NULL,
    cover_url       VARCHAR(500)  NULL,
    github_url      VARCHAR(255)  NULL,
    linkedin_url    VARCHAR(255)  NULL,
    portfolio_url   VARCHAR(255)  NULL,
    is_open_to_team BIT           NOT NULL CONSTRAINT DF_profiles_open DEFAULT 1,
    updated_at      DATETIME2(0)  NOT NULL CONSTRAINT DF_profiles_updated DEFAULT SYSDATETIME(),
    CONSTRAINT FK_profiles_user FOREIGN KEY (user_id)
        REFERENCES dbo.users(user_id) ON DELETE CASCADE
);
GO

/* ---------------------------------------------------------------------
   5. Yetenekler
      level: 1 = baslangic, 2 = orta, 3 = ileri, 4 = uzman
      (sayisal tutulur ki eslesme sorgusunda >= ile karsilastirilabilsin)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.skills (
    skill_id INT IDENTITY(1,1) CONSTRAINT PK_skills PRIMARY KEY,
    name     NVARCHAR(80) NOT NULL CONSTRAINT UQ_skills_name UNIQUE,
    category NVARCHAR(60) NULL
);
GO

CREATE TABLE dbo.user_skills (
    user_id  INT     NOT NULL,
    skill_id INT     NOT NULL,
    level    TINYINT NOT NULL CONSTRAINT DF_user_skills_level DEFAULT 1,
    CONSTRAINT PK_user_skills PRIMARY KEY (user_id, skill_id),
    CONSTRAINT FK_user_skills_user  FOREIGN KEY (user_id)  REFERENCES dbo.users(user_id)   ON DELETE CASCADE,
    CONSTRAINT FK_user_skills_skill FOREIGN KEY (skill_id) REFERENCES dbo.skills(skill_id) ON DELETE CASCADE,
    CONSTRAINT CK_user_skills_level CHECK (level BETWEEN 1 AND 4)
);
CREATE INDEX IX_user_skills_skill ON dbo.user_skills(skill_id);
GO

/* ---------------------------------------------------------------------
   6. Takip (kullanici - kullanici, N:M)
      Not: SQL Server ayni tabloya giden iki CASCADE yoluna izin vermez,
      bu yuzden following_id tarafi NO ACTION'dir.
   --------------------------------------------------------------------- */
CREATE TABLE dbo.follows (
    follower_id  INT          NOT NULL,
    following_id INT          NOT NULL,
    created_at   DATETIME2(0) NOT NULL CONSTRAINT DF_follows_created DEFAULT SYSDATETIME(),
    CONSTRAINT PK_follows PRIMARY KEY (follower_id, following_id),
    CONSTRAINT FK_follows_follower  FOREIGN KEY (follower_id)  REFERENCES dbo.users(user_id) ON DELETE CASCADE,
    CONSTRAINT FK_follows_following FOREIGN KEY (following_id) REFERENCES dbo.users(user_id) ON DELETE NO ACTION,
    CONSTRAINT CK_follows_self CHECK (follower_id <> following_id)
);
GO

/* ---------------------------------------------------------------------
   7. Kulupler ve uyelikler
   --------------------------------------------------------------------- */
CREATE TABLE dbo.clubs (
    club_id     INT IDENTITY(1,1) CONSTRAINT PK_clubs PRIMARY KEY,
    name        NVARCHAR(150) NOT NULL CONSTRAINT UQ_clubs_name UNIQUE,
    description NVARCHAR(MAX) NULL,
    logo_url    VARCHAR(500)  NULL,
    advisor_id  INT           NULL,   -- danisman akademisyen
    created_at  DATETIME2(0)  NOT NULL CONSTRAINT DF_clubs_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_clubs_advisor FOREIGN KEY (advisor_id)
        REFERENCES dbo.users(user_id) ON DELETE NO ACTION
);
GO

CREATE TABLE dbo.club_members (
    club_id   INT          NOT NULL,
    user_id   INT          NOT NULL,
    is_admin  BIT          NOT NULL CONSTRAINT DF_club_members_admin DEFAULT 0,
    joined_at DATETIME2(0) NOT NULL CONSTRAINT DF_club_members_joined DEFAULT SYSDATETIME(),
    CONSTRAINT PK_club_members PRIMARY KEY (club_id, user_id),
    CONSTRAINT FK_club_members_club FOREIGN KEY (club_id) REFERENCES dbo.clubs(club_id) ON DELETE CASCADE,
    CONSTRAINT FK_club_members_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id) ON DELETE CASCADE
);
GO

/* ---------------------------------------------------------------------
   8. Projeler (takim arkadasi eslesmesinin cekirdegi)
      status: open | in_progress | completed | closed
      project_members.role: owner | member | advisor
      project_applications.status: pending | accepted | rejected | withdrawn
   --------------------------------------------------------------------- */
CREATE TABLE dbo.projects (
    project_id  INT IDENTITY(1,1) CONSTRAINT PK_projects PRIMARY KEY,
    owner_id    INT           NOT NULL,
    title       NVARCHAR(200) NOT NULL,
    description NVARCHAR(MAX) NULL,
    category    NVARCHAR(80)  NULL,   -- bitirme projesi, TEKNOFEST, yarisma, akademik yayin...
    status      VARCHAR(20)   NOT NULL CONSTRAINT DF_projects_status DEFAULT 'open',
    repo_url    VARCHAR(255)  NULL,
    max_members TINYINT       NULL CONSTRAINT DF_projects_max DEFAULT 5,
    created_at  DATETIME2(0)  NOT NULL CONSTRAINT DF_projects_created DEFAULT SYSDATETIME(),
    updated_at  DATETIME2(0)  NOT NULL CONSTRAINT DF_projects_updated DEFAULT SYSDATETIME(),
    CONSTRAINT FK_projects_owner FOREIGN KEY (owner_id) REFERENCES dbo.users(user_id) ON DELETE CASCADE,
    CONSTRAINT CK_projects_status CHECK (status IN ('open','in_progress','completed','closed'))
);
CREATE INDEX IX_projects_status ON dbo.projects(status);
GO

CREATE TABLE dbo.project_members (
    project_id INT         NOT NULL,
    user_id    INT         NOT NULL,
    role       VARCHAR(10) NOT NULL CONSTRAINT DF_project_members_role DEFAULT 'member',
    joined_at  DATETIME2(0) NOT NULL CONSTRAINT DF_project_members_joined DEFAULT SYSDATETIME(),
    CONSTRAINT PK_project_members PRIMARY KEY (project_id, user_id),
    CONSTRAINT FK_pm_project FOREIGN KEY (project_id) REFERENCES dbo.projects(project_id) ON DELETE CASCADE,
    CONSTRAINT FK_pm_user    FOREIGN KEY (user_id)    REFERENCES dbo.users(user_id)       ON DELETE NO ACTION,
    CONSTRAINT CK_pm_role CHECK (role IN ('owner','member','advisor'))
);
GO

-- Projenin ihtiyac duydugu yetenekler (eslesme algoritmasi bunu kullanir)
CREATE TABLE dbo.project_required_skills (
    project_id INT     NOT NULL,
    skill_id   INT     NOT NULL,
    min_level  TINYINT NOT NULL CONSTRAINT DF_prs_level DEFAULT 1,
    CONSTRAINT PK_project_required_skills PRIMARY KEY (project_id, skill_id),
    CONSTRAINT FK_prs_project FOREIGN KEY (project_id) REFERENCES dbo.projects(project_id) ON DELETE CASCADE,
    CONSTRAINT FK_prs_skill   FOREIGN KEY (skill_id)   REFERENCES dbo.skills(skill_id)     ON DELETE CASCADE,
    CONSTRAINT CK_prs_level CHECK (min_level BETWEEN 1 AND 4)
);
GO

CREATE TABLE dbo.project_applications (
    application_id INT IDENTITY(1,1) CONSTRAINT PK_project_applications PRIMARY KEY,
    project_id     INT           NOT NULL,
    applicant_id   INT           NOT NULL,
    message        NVARCHAR(MAX) NULL,
    status         VARCHAR(10)   NOT NULL CONSTRAINT DF_pa_status DEFAULT 'pending',
    created_at     DATETIME2(0)  NOT NULL CONSTRAINT DF_pa_created DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_pa_project_applicant UNIQUE (project_id, applicant_id),
    CONSTRAINT FK_pa_project   FOREIGN KEY (project_id)   REFERENCES dbo.projects(project_id) ON DELETE CASCADE,
    CONSTRAINT FK_pa_applicant FOREIGN KEY (applicant_id) REFERENCES dbo.users(user_id)       ON DELETE NO ACTION,
    CONSTRAINT CK_pa_status CHECK (status IN ('pending','accepted','rejected','withdrawn'))
);
GO

/* ---------------------------------------------------------------------
   9. Gonderiler (akis), medya, begeni, yorum
      posts.type: project | announcement | event | general
      post_media.type: image | video | document | link
   --------------------------------------------------------------------- */
CREATE TABLE dbo.posts (
    post_id    INT IDENTITY(1,1) CONSTRAINT PK_posts PRIMARY KEY,
    author_id  INT           NOT NULL,
    club_id    INT           NULL,   -- kulup duyurusu ise
    project_id INT           NULL,   -- proje paylasimi ise
    type       VARCHAR(15)   NOT NULL CONSTRAINT DF_posts_type DEFAULT 'general',
    content    NVARCHAR(MAX) NULL,
    is_deleted BIT           NOT NULL CONSTRAINT DF_posts_deleted DEFAULT 0,
    created_at DATETIME2(0)  NOT NULL CONSTRAINT DF_posts_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_posts_author  FOREIGN KEY (author_id)  REFERENCES dbo.users(user_id)       ON DELETE CASCADE,
    CONSTRAINT FK_posts_club    FOREIGN KEY (club_id)    REFERENCES dbo.clubs(club_id)       ON DELETE NO ACTION,
    CONSTRAINT FK_posts_project FOREIGN KEY (project_id) REFERENCES dbo.projects(project_id) ON DELETE NO ACTION,
    CONSTRAINT CK_posts_type CHECK (type IN ('project','announcement','event','general'))
);
CREATE INDEX IX_posts_author  ON dbo.posts(author_id);
CREATE INDEX IX_posts_created ON dbo.posts(created_at DESC);
GO

CREATE TABLE dbo.post_media (
    media_id   INT IDENTITY(1,1) CONSTRAINT PK_post_media PRIMARY KEY,
    post_id    INT          NOT NULL,
    type       VARCHAR(10)  NOT NULL CONSTRAINT DF_post_media_type DEFAULT 'image',
    url        VARCHAR(500) NOT NULL,
    sort_order SMALLINT     NOT NULL CONSTRAINT DF_post_media_sort DEFAULT 0,
    CONSTRAINT FK_post_media_post FOREIGN KEY (post_id) REFERENCES dbo.posts(post_id) ON DELETE CASCADE,
    CONSTRAINT CK_post_media_type CHECK (type IN ('image','video','document','link'))
);
GO

CREATE TABLE dbo.post_likes (
    post_id    INT          NOT NULL,
    user_id    INT          NOT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_post_likes_created DEFAULT SYSDATETIME(),
    CONSTRAINT PK_post_likes PRIMARY KEY (post_id, user_id),
    CONSTRAINT FK_post_likes_post FOREIGN KEY (post_id) REFERENCES dbo.posts(post_id) ON DELETE CASCADE,
    CONSTRAINT FK_post_likes_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id) ON DELETE NO ACTION
);
GO

CREATE TABLE dbo.comments (
    comment_id        INT IDENTITY(1,1) CONSTRAINT PK_comments PRIMARY KEY,
    post_id           INT           NOT NULL,
    user_id           INT           NOT NULL,
    parent_comment_id INT           NULL,   -- yanit zinciri
    content           NVARCHAR(MAX) NOT NULL,
    created_at        DATETIME2(0)  NOT NULL CONSTRAINT DF_comments_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_comments_post   FOREIGN KEY (post_id)           REFERENCES dbo.posts(post_id)       ON DELETE CASCADE,
    CONSTRAINT FK_comments_user   FOREIGN KEY (user_id)           REFERENCES dbo.users(user_id)       ON DELETE NO ACTION,
    CONSTRAINT FK_comments_parent FOREIGN KEY (parent_comment_id) REFERENCES dbo.comments(comment_id) ON DELETE NO ACTION
);
CREATE INDEX IX_comments_post ON dbo.comments(post_id);
GO

/* ---------------------------------------------------------------------
   10. Etkinlikler
   --------------------------------------------------------------------- */
CREATE TABLE dbo.events (
    event_id    INT IDENTITY(1,1) CONSTRAINT PK_events PRIMARY KEY,
    club_id     INT           NOT NULL,
    created_by  INT           NOT NULL,
    title       NVARCHAR(200) NOT NULL,
    description NVARCHAR(MAX) NULL,
    location    NVARCHAR(200) NULL,
    starts_at   DATETIME2(0)  NOT NULL,
    ends_at     DATETIME2(0)  NULL,
    CONSTRAINT FK_events_club FOREIGN KEY (club_id)    REFERENCES dbo.clubs(club_id) ON DELETE CASCADE,
    CONSTRAINT FK_events_user FOREIGN KEY (created_by) REFERENCES dbo.users(user_id) ON DELETE NO ACTION,
    CONSTRAINT CK_events_dates CHECK (ends_at IS NULL OR ends_at >= starts_at)
);
GO

CREATE TABLE dbo.event_attendees (
    event_id      INT          NOT NULL,
    user_id       INT          NOT NULL,
    registered_at DATETIME2(0) NOT NULL CONSTRAINT DF_event_att_reg DEFAULT SYSDATETIME(),
    CONSTRAINT PK_event_attendees PRIMARY KEY (event_id, user_id),
    CONSTRAINT FK_event_att_event FOREIGN KEY (event_id) REFERENCES dbo.events(event_id) ON DELETE CASCADE,
    CONSTRAINT FK_event_att_user  FOREIGN KEY (user_id)  REFERENCES dbo.users(user_id)   ON DELETE CASCADE
);
GO

/* ---------------------------------------------------------------------
   11. Bildirimler
       type: like | comment | follow | application | announcement | system
   --------------------------------------------------------------------- */
CREATE TABLE dbo.notifications (
    notification_id INT IDENTITY(1,1) CONSTRAINT PK_notifications PRIMARY KEY,
    user_id         INT          NOT NULL,   -- alici
    actor_id        INT          NULL,       -- islemi yapan
    type            VARCHAR(15)  NOT NULL,
    post_id         INT          NULL,
    project_id      INT          NULL,
    is_read         BIT          NOT NULL CONSTRAINT DF_notif_read DEFAULT 0,
    created_at      DATETIME2(0) NOT NULL CONSTRAINT DF_notif_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_notif_user    FOREIGN KEY (user_id)    REFERENCES dbo.users(user_id)       ON DELETE CASCADE,
    CONSTRAINT FK_notif_actor   FOREIGN KEY (actor_id)   REFERENCES dbo.users(user_id)       ON DELETE NO ACTION,
    CONSTRAINT FK_notif_post    FOREIGN KEY (post_id)    REFERENCES dbo.posts(post_id)       ON DELETE NO ACTION,
    CONSTRAINT FK_notif_project FOREIGN KEY (project_id) REFERENCES dbo.projects(project_id) ON DELETE NO ACTION,
    CONSTRAINT CK_notif_type CHECK (type IN ('like','comment','follow','application','announcement','system'))
);
CREATE INDEX IX_notifications_user ON dbo.notifications(user_id, is_read);
GO

/* ---------------------------------------------------------------------
   12. Baslangic verisi (ornek)
   --------------------------------------------------------------------- */
INSERT INTO dbo.departments (name, faculty) VALUES
    (N'Bilgisayar Programcılığı', N'Meslek Yüksekokulu'),
    (N'Bilgisayar Mühendisliği',  N'Mühendislik Fakültesi'),
    (N'Grafik Tasarım',           N'Güzel Sanatlar Fakültesi');

INSERT INTO dbo.skills (name, category) VALUES
    (N'Flutter',        N'Yazılım'),
    (N'React Native',   N'Yazılım'),
    (N'Node.js',        N'Yazılım'),
    (N'Python',         N'Yazılım'),
    (N'SQL',            N'Veri'),
    (N'Veri Analizi',   N'Veri'),
    (N'Grafik Tasarım', N'Tasarım'),
    (N'UI/UX',          N'Tasarım');
GO

/* ---------------------------------------------------------------------
   13. Ornek: Takim arkadasi eslesme sorgusu
       Bir projenin gerekli yeteneklerine en cok uyan ogrencileri listeler.
   --------------------------------------------------------------------- */
/*
DECLARE @project_id INT = 1;

SELECT u.user_id, u.first_name, u.last_name, COUNT(*) AS eslesen_yetenek
FROM dbo.project_required_skills prs
JOIN dbo.user_skills us ON us.skill_id = prs.skill_id AND us.level >= prs.min_level
JOIN dbo.users u        ON u.user_id = us.user_id
JOIN dbo.profiles p     ON p.user_id = u.user_id AND p.is_open_to_team = 1
WHERE prs.project_id = @project_id
  AND u.user_id NOT IN (SELECT user_id FROM dbo.project_members WHERE project_id = @project_id)
GROUP BY u.user_id, u.first_name, u.last_name
ORDER BY eslesen_yetenek DESC;
*/
