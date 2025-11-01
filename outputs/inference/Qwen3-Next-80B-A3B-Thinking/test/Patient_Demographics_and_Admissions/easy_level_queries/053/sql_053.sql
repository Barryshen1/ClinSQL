WITH aki_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND d.icd_code LIKE 'N17%'
),
readmission_flags AS (
  SELECT 
    a.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime > a.dischtime
        AND a2.admittime <= a.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmitted
  FROM aki_admissions a
)
SELECT SQRT((SUM(readmitted) / COUNT(*)) * (1 - SUM(readmitted) / COUNT(*))) AS std_dev
FROM readmission_flags;