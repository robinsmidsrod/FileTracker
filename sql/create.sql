/*==========================================================================*/
/* Project Filename:    K:\internt\ERD\FileTracker\FileTracker.dez          */
/* Project Name:                                                            */
/* Author:                                                                  */
/* DBMS:                PostgreSQL 7                                        */
/* Copyright:                                                               */
/* Generated on:        15.06.2004 13:05:40                                 */
/*==========================================================================*/

/*==========================================================================*/
/*  Tables                                                                  */
/*==========================================================================*/

CREATE TABLE file (
    file_id VARCHAR(36) NOT NULL,
    path VARCHAR(512) NOT NULL,
    size INT4 NOT NULL,
    ctime TIMESTAMP NOT NULL,
    mtime TIMESTAMP NOT NULL,
    md5 VARCHAR(32) NOT NULL,
    root_id VARCHAR(36) NOT NULL,
    snapshot_id VARCHAR(36) NOT NULL,
    CONSTRAINT PK_file PRIMARY KEY (file_id)
);

CREATE TABLE snapshot (
    snapshot_id VARCHAR(36) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    CONSTRAINT PK_snapshot PRIMARY KEY (snapshot_id)
);

CREATE TABLE root (
    root_id VARCHAR(36) NOT NULL,
    path VARCHAR(512) NOT NULL,
    CONSTRAINT PK_root PRIMARY KEY (root_id)
);

/*==========================================================================*/
/*  Foreign Keys                                                            */
/*==========================================================================*/

ALTER TABLE file
    ADD FOREIGN KEY (root_id) REFERENCES root (root_id) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE file
    ADD FOREIGN KEY (snapshot_id) REFERENCES snapshot (snapshot_id) ON DELETE RESTRICT ON UPDATE CASCADE;

/*==========================================================================*/
/*  Indexes                                                                 */
/*==========================================================================*/

CREATE INDEX IDX_path ON file (path);

CREATE INDEX IDX_size ON file (size);

CREATE INDEX IDX_ctime ON file (ctime);

CREATE INDEX IDX_mtime ON file (mtime);

CREATE INDEX IDX_md5 ON file (md5);

CREATE UNIQUE INDEX IDX_unique_path ON file (path, root_id);

CREATE INDEX IDX_start_time ON snapshot (start_time);

CREATE INDEX IDX_end_time ON snapshot (end_time);

/*==========================================================================*/
/*  Sequences                                                               */
/*==========================================================================*/

/*==========================================================================*/
/*  Procedures                                                              */
/*==========================================================================*/

/*==========================================================================*/
/*  Triggers                                                                */
/*==========================================================================*/
