WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND d.icd_version = 10
    AND d.icd_code IN ('K92.0', 'K92.1', 'K92.2')
),

los_data AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS has_icu
  FROM cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id, a.admittime, a.dischtime
),

diagnostics_count AS (
  SELECT
    hc.hadm_id,
    COUNT(*) AS num_diagnostics
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON hc.hcpcs_cd = d.code
  WHERE
    d.short_description LIKE '%X-ray%' OR
    d.short_description LIKE '%CT%' OR
    d.short_description LIKE '%MRI%' OR
    d.short_description LIKE '%ultrasound%' OR
    d.short_description LIKE '%ECG%' OR
    d.short_description LIKE '%electrocardiogram%' OR
    d.short_description LIKE '%EEG%' OR
    d.short_description LIKE '%electroencephalogram%' OR
    d.short_description LIKE '%PFT%' OR
    d.short_description LIKE '%pulmonary function%' OR
    d.short_description LIKE '%spirometry%'
  GROUP BY hc.hadm_id
)

SELECT
  los_group,
  has_icu,
  AVG(COALESCE(num_diagnostics, 0)) AS mean_diagnostics
FROM los_data
LEFT JOIN diagnostics_count USING (hadm_id)
WHERE los_group IS NOT NULL
GROUP BY los_group, has_icu;