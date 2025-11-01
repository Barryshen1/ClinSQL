WITH pneumonia_patients AS (
  -- Identify male patients aged 43-53 with pneumonia
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      -- Common ICD-9/10 codes for pneumonia
      (d.icd_version = 9 AND d.icd_code IN ('486', '482.9', '481', '480.9'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('J18.9', 'J15.9', 'J13', 'J14', 'J12.9'))
    )
),

first_icu_stays AS (
  -- Get the first ICU stay for each patient
  SELECT
    pp.subject_id,
    pp.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY pp.subject_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    pneumonia_patients pp
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pp.subject_id = i.subject_id AND pp.hadm_id = i.hadm_id
)

-- Calculate the 25th percentile of ICU LOS for first ICU stays
SELECT
  PERCENTILE_DISC(los_days, 0.25) AS percentile_25_icu_los_days
FROM
  first_icu_stays
WHERE
  icu_stay_rank = 1  -- Only first ICU stay per patient
;