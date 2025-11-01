WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%type 2 diabetes mellitus%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%heart failure%'
    )
),

drug_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    /* Flag for any GLP-1 RA prescription in first 12 hours */
    MAX(
      CASE
        WHEN pr.starttime BETWEEN c.admittime
                             AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
        THEN 1 ELSE 0
      END
    ) AS init_in_12h,
    /* Flag for any GLP-1 RA prescription in last 24 hours pre-discharge */
    MAX(
      CASE
        WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
                             AND c.dischtime
        THEN 1 ELSE 0
      END
    ) AS in_last_24h
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.subject_id = c.subject_id
     AND pr.hadm_id = c.hadm_id
     AND (
       LOWER(pr.drug) LIKE '%exenatide%'
       OR LOWER(pr.drug) LIKE '%liraglutide%'
       OR LOWER(pr.drug) LIKE '%dulaglutide%'
       OR LOWER(pr.drug) LIKE '%semaglutide%'
       OR LOWER(pr.drug) LIKE '%lixisenatide%'
       OR LOWER(pr.drug) LIKE '%albiglutide%'
     )
  GROUP BY
    c.subject_id,
    c.hadm_id
)

SELECT
  COUNT(1) AS total_admissions,
  SUM(init_in_12h) AS initiated_in_first_12h,
  SUM(in_last_24h) AS in_final_24h,
  ROUND(100.0 * SUM(init_in_12h) / COUNT(1), 1) AS pct_initiated_first_12h,
  ROUND(100.0 * SUM(in_last_24h) / COUNT(1), 1) AS pct_in_final_24h,
  ROUND(
    100.0 * SUM(in_last_24h) / COUNT(1)
    - 100.0 * SUM(init_in_12h) / COUNT(1),
    1
  ) AS net_pct_point_change
FROM
  drug_events;