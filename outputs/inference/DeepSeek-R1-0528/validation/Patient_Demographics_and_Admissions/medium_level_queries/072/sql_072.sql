WITH first_service AS (
  SELECT 
    s.hadm_id, 
    s.curr_service AS admitting_service
  FROM `physionet-data.mimiciv_3_1_hosp.services` s
  INNER JOIN (
    SELECT 
      hadm_id, 
      MIN(transfertime) AS first_transfer
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    GROUP BY hadm_id
  ) fs 
    ON s.hadm_id = fs.hadm_id 
    AND s.transfertime = fs.first_transfer
),
cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    fs.admitting_service
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN first_service fs
    ON adm.hadm_id = fs.hadm_id
  WHERE 
    pat.gender = 'M'
    AND fs.admitting_service = 'MEDICINE'
),
cohort_filtered AS (
  SELECT 
    *,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    END AS discharge_category
  FROM cohort
  WHERE 
    age_at_admission BETWEEN 74 AND 84
    AND (hospital_expire_flag = 1 OR discharge_location IN ('HOME', 'HOSPICE'))
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  COUNTIF(los_days <= 5) / COUNT(*) AS proportion_lte_5_days
FROM cohort_filtered
GROUP BY discharge_category;