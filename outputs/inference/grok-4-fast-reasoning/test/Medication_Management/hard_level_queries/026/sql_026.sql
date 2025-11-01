WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(icd.long_title) LIKE '%pneumonia%'
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.dischtime IS NOT NULL
),

scores AS (
  SELECT
    c.*,
    COUNT(DISTINCT pres.drug) AS num_drugs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag,
    c.gender, c.anchor_age, c.los_days
),

readmits AS (
  SELECT
    s.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = s.subject_id
        AND a2.hadm_id != s.hadm_id
        AND a2.admittime > s.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(s.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d
  FROM scores s
),

final_data AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY num_drugs) AS tertile
  FROM readmits
)

SELECT
  tertile,
  COUNT(*) AS count_admissions,
  MIN(num_drugs) AS min_score,
  AVG(num_drugs) AS avg_score,
  MAX(num_drugs) AS max_score,
  AVG(los_days) AS mean_los_days,
  (AVG(hospital_expire_flag) * 100) AS in_hospital_mortality_pct,
  (AVG(IF(readmit_30d, 1.0, 0.0)) * 100) AS readmission_30d_pct
FROM final_data
GROUP BY tertile
ORDER BY tertile;