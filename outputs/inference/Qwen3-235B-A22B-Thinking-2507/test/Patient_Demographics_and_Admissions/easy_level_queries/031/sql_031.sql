WITH hf_admissions AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON d.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%') 
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
first_hf_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM hf_admissions
),
index_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    dischtime
  FROM first_hf_admission
  WHERE rn = 1
    AND age_at_admission BETWEEN 38 AND 48
    AND dischtime IS NOT NULL
),
readmission_flag AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.dischtime,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_admissions i
)
SELECT 
  AVG(readmitted_30d) AS readmission_rate
FROM readmission_flag;