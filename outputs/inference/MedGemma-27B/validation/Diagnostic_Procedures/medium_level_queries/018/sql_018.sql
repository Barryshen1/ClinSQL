WITH PatientStroke AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'I60' -- Hemorrhagic stroke ICD-10 code
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
UltrasoundCounts AS (
  SELECT
    ps.subject_id,
    h.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS ultrasound_count
  FROM
    PatientStroke AS ps
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON ps.subject_id = h.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON h.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd LIKE '76%' -- HCPCS codes starting with 76 are typically ultrasounds
  GROUP BY
    ps.subject_id,
    h.hadm_id
),
AdmissionLength AS (
  SELECT
    uc.subject_id,
    uc.hadm_id,
    uc.ultrasound_count,
    DATE_DIFF(h.dischtime, h.admittime, DAY) AS admission_length
  FROM
    UltrasoundCounts AS uc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON uc.hadm_id = h.hadm_id
)
SELECT
  CASE
    WHEN admission_length BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN admission_length BETWEEN 5 AND 7
    THEN '5-7 days'
    ELSE 'Other'
  END AS stay_length_group,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM
  AdmissionLength
WHERE
  admission_length BETWEEN 1 AND 7
GROUP BY
  stay_length_group
ORDER BY
  stay_length_group;