WITH cardiac_arrest_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (dx.icd_version = 9 AND dx.icd_code = '4275') -- ICD-9 cardiac arrest
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I46%') -- ICD-10 cardiac arrest
    )
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM cardiac_arrest_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_score AS (
  SELECT
    c.*,
    m.complexity_score,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    -- flag for 30-day readmission
    IF((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    ) > 0, 1, 0) AS readmit_30d
  FROM cardiac_arrest_cohort c
  LEFT JOIN med_complexity m
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),
cohort_with_quintile AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY complexity_score) AS complexity_quintile
  FROM cohort_with_score
)
SELECT
  complexity_quintile,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(complexity_score) AS avg_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los) AS avg_los_days,
  100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hosp_mortality_pct,
  100 * SUM(readmit_30d) / COUNT(*) AS readmit_30d_pct
FROM cohort_with_quintile
GROUP BY complexity_quintile
ORDER BY complexity_quintile;