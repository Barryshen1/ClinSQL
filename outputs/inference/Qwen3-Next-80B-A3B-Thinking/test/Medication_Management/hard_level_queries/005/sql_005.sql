WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE (di.long_title LIKE '%liver failure%' OR di.long_title LIKE '%hepatic failure%')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),
medication_scores AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS med_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
  GROUP BY c.hadm_id
),
readmission AS (
  SELECT
    a1.hadm_id,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmission_flag
  FROM cohort a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
  GROUP BY a1.hadm_id
),
combined AS (
  SELECT
    c.hadm_id,
    ms.med_score,
    c.los_days,
    c.hospital_expire_flag,
    r.readmission_flag,
    NTILE(5) OVER (ORDER BY ms.med_score) AS quintile
  FROM cohort c
  LEFT JOIN medication_scores ms ON c.hadm_id = ms.hadm_id
  LEFT JOIN readmission r ON c.hadm_id = r.hadm_id
)
SELECT
  quintile,
  COUNT(*) AS n,
  MIN(med_score) AS min_score,
  MAX(med_score) AS max_score,
  AVG(med_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(readmission_flag) * 100 AS thirty_day_readmission_pct
FROM combined
GROUP BY quintile
ORDER BY quintile;