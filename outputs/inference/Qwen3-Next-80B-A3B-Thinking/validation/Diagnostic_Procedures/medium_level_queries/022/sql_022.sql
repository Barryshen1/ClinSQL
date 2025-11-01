WITH admissions_data AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
heart_failure_diagnoses AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE '428%'
),
non_invasive_procedures AS (
  SELECT
    hcpcsevents.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpcsevents
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_hcpcs
    ON hcpcsevents.hcpcs_cd = d_hcpcs.code
  WHERE
    d_hcpcs.short_description LIKE '%X-ray%'
    OR d_hcpcs.short_description LIKE '%ECG%'
    OR d_hcpcs.short_description LIKE '%PFT%'
    OR d_hcpcs.short_description LIKE '%CT%'
    OR d_hcpcs.short_description LIKE '%MRI%'
    OR d_hcpcs.short_description LIKE '%ultrasound%'
  GROUP BY hcpcsevents.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE NULL
  END AS los_group,
  CASE
    WHEN admission_type IN ('Urgent', 'Emergency', 'Trauma') THEN 'ED/Urgent'
    WHEN admission_type = 'Elective' THEN 'Elective'
    ELSE NULL
  END AS admission_type_group,
  AVG(COALESCE(nip.procedure_count, 0)) AS mean_procedures
FROM admissions_data a
JOIN heart_failure_diagnoses hfd
  ON a.hadm_id = hfd.hadm_id
LEFT JOIN non_invasive_procedures nip
  ON a.hadm_id = nip.hadm_id
WHERE
  a.age_at_admission = 74
  AND a.los_days BETWEEN 1 AND 7
  AND a.admission_type IN ('Urgent', 'Emergency', 'Trauma', 'Elective')
GROUP BY los_group, admission_type_group
HAVING los_group IS NOT NULL AND admission_type_group IS NOT NULL;