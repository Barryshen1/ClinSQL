WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dicd.long_title) LIKE '%multi-trauma%'
       OR LOWER(dicd.long_title) LIKE '%polytrauma%'
       OR LOWER(dicd.long_title) LIKE '%multiple trauma%'
),

medication_complexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),

los_mortality AS (
  SELECT
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

readmission_30d AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
),

combined AS (
  SELECT
    c.hadm_id,
    mc.med_complexity_score,
    lm.los_days,
    lm.hospital_expire_flag,
    r.readmit_30d,
    NTILE(3) OVER (ORDER BY mc.med_complexity_score) AS tertile
  FROM cohort c
  LEFT JOIN medication_complexity mc ON c.hadm_id = mc.hadm_id
  LEFT JOIN los_mortality lm ON c.hadm_id = lm.hadm_id
  LEFT JOIN readmission_30d r ON c.hadm_id = r.hadm_id
)

SELECT
  tertile,
  COUNT(hadm_id) AS admissions,
  AVG(med_complexity_score) AS mean_med_complexity,
  MIN(med_complexity_score) AS min_med_complexity,
  MAX(med_complexity_score) AS max_med_complexity,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(CAST(readmit_30d AS FLOAT64)) * 100 AS readmission_30d_percent
FROM combined
GROUP BY tertile
ORDER BY tertile;