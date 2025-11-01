WITH base_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Calculate hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    -- Determine if patient had ICU stay
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Calculate age at admission
  CROSS JOIN UNNEST([p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)]) AS age_at_adm
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND age_at_adm BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '78552')
          OR (d.icd_version = 10 AND d.icd_code = 'R6521')
        )
    )
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),

ultrasound_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS count_ultrasound
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    (d.short_description LIKE '%ULTRASOUND%' OR d.short_description LIKE '%ECHO%')
  GROUP BY h.hadm_id
),

admissions_with_ultrasound AS (
  SELECT 
    bp.hadm_id,
    bp.hospital_los_days,
    bp.icu_flag,
    COALESCE(uc.count_ultrasound, 0) AS count_ultrasound
  FROM base_population bp
  LEFT JOIN ultrasound_counts uc
    ON bp.hadm_id = uc.hadm_id
  WHERE 
    bp.hospital_los_days BETWEEN 1 AND 7  -- Only include admissions with LOS 1-7 days
)

SELECT 
  CASE 
    WHEN hospital_los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN hospital_los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  CASE icu_flag
    WHEN 1 THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  APPROX_QUANTILES(count_ultrasound, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(count_ultrasound, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(count_ultrasound, 1000)[OFFSET(750)] AS p75,
  COUNT(*) AS num_admissions
FROM admissions_with_ultrasound
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;