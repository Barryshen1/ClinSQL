WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%heart failure%'
    )
),

drug_initiations AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.drug,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' THEN 'oral_agent'
      ELSE NULL
    END AS drug_class,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id, pr.drug ORDER BY pr.starttime) AS rn
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime IS NOT NULL
),

first_initiations AS (
  SELECT *
  FROM drug_initiations
  WHERE rn = 1
),

time_window_flags AS (
  SELECT
    hadm_id,
    drug_class,
    CASE
      WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) THEN 1
      ELSE 0
    END AS in_0_48h,
    CASE
      WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AND dischtime THEN 1
      ELSE 0
    END AS in_final_72h
  FROM
    first_initiations
  WHERE
    drug_class IN ('insulin', 'oral_agent')
),

initiation_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN drug_class = 'insulin' AND in_0_48h = 1 THEN 1 ELSE 0 END) AS insulin_0_48h,
    MAX(CASE WHEN drug_class = 'oral_agent' AND in_0_48h = 1 THEN 1 ELSE 0 END) AS oral_0_48h,
    MAX(CASE WHEN drug_class = 'insulin' AND in_final_72h = 1 THEN 1 ELSE 0 END) AS insulin_final_72h,
    MAX(CASE WHEN drug_class = 'oral_agent' AND in_final_72h = 1 THEN 1 ELSE 0 END) AS oral_final_72h
  FROM
    time_window_flags
  GROUP BY
    hadm_id
),

rates AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(insulin_0_48h) AS insulin_rate_0_48h,
    AVG(oral_0_48h) AS oral_rate_0_48h,
    AVG(insulin_final_72h) AS insulin_rate_final_72h,
    AVG(oral_final_72h) AS oral_rate_final_72h
  FROM
    initiation_flags
)

SELECT
  total_patients,
  insulin_rate_0_48h,
  oral_rate_0_48h,
  (insulin_rate_0_48h - oral_rate_0_48h) * 100 AS net_change_0_48h_pp,
  insulin_rate_final_72h,
  oral_rate_final_72h,
  (insulin_rate_final_72h - oral_rate_final_72h) * 100 AS net_change_final_72h_pp
FROM
  rates;