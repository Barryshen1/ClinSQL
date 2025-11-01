WITH hepatic_hadm AS (
  -- Identify admissions with any diagnosis description suggestive of hepatic / liver failure
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%hepatic%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%liver failure%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hepatic failure%'
),

cohort AS (
  -- Male inpatients aged 43-53 with a hepatic failure diagnosis on the admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hepatic_hadm hh
    ON a.hadm_id = hh.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

meds_first_72h AS (
  -- Count distinct prescribed drugs (by normalized drug name) started within first 72 hours of admission
  SELECT
    c.hadm_id,
    COUNT(DISTINCT LOWER(TRIM(prescription.drug))) AS med_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prescription
    ON prescription.hadm_id = c.hadm_id
   AND prescription.starttime BETWEEN c.admittime
                                AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),

readmit_30d AS (
  -- Flag admissions that have any subsequent admission for the same subject within 30 days of discharge
  SELECT
    c.hadm_id,
    CASE WHEN COUNT(DISTINCT a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_within_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
   AND a2.admittime > c.dischtime
   AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.hadm_id
),

per_admission AS (
  -- Combine cohort with medication score and readmit flag; default med_score = 0 if none
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(m.med_score, 0) AS med_score,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(r.readmit_within_30d, 0) AS readmit_within_30d
  FROM cohort c
  LEFT JOIN meds_first_72h m
    ON c.hadm_id = m.hadm_id
  LEFT JOIN readmit_30d r
    ON c.hadm_id = r.hadm_id
),

with_quintile AS (
  -- Assign quintiles based on medication score distribution
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_score) AS med_score_quintile
  FROM per_admission
)

-- Final aggregated report per quintile
SELECT
  med_score_quintile AS quintile,
  COUNT(1) AS n,
  MIN(med_score) AS med_score_min,
  MAX(med_score) AS med_score_max,
  ROUND(AVG(med_score), 2) AS med_score_mean,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * AVG(CAST(readmit_within_30d AS FLOAT64)), 2) AS readmit_30d_pct
FROM with_quintile
GROUP BY med_score_quintile
ORDER BY med_score_quintile;