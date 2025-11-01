WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND d.icd_code LIKE 'I46%'
    AND d.icd_version = 10
),

medication_complexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 7 DAY
  GROUP BY c.hadm_id
),

readmission AS (
  SELECT
    c.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= c.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmitted
  FROM cohort c
),

quintiles AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    mc.med_count,
    c.los,
    c.hospital_expire_flag,
    r.readmitted,
    NTILE(5) OVER (ORDER BY mc.med_count) AS quintile
  FROM cohort c
  JOIN medication_complexity mc ON c.hadm_id = mc.hadm_id
  JOIN readmission r ON c.hadm_id = r.hadm_id
)

SELECT
  quintile,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_score,
  MIN(med_count) AS min_score,
  MAX(med_count) AS max_score,
  AVG(los) AS avg_los,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS inhospital_mortality_pct,
  (SUM(readmitted) * 100.0 / COUNT(*)) AS readmission_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;