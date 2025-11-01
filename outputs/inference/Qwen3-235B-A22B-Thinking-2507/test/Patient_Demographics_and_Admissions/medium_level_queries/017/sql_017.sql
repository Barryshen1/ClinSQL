WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` 
      WHERE hadm_id = adm.hadm_id
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 38 AND 48
)
SELECT
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location = 'HOME' THEN 'home'
    ELSE 'facility'
  END AS discharge_category,
  AVG(hospital_los) AS mean_los,
  APPROX_QUANTILES(hospital_los, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(hospital_los, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(hospital_los, 1000)[OFFSET(900)] AS p90_los
FROM filtered_admissions
GROUP BY discharge_category
ORDER BY discharge_category;