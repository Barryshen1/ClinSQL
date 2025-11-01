WITH upper_gi_bleeding_codes AS (
  -- Define relevant ICD codes for upper GI bleeding (example codes; adjust as needed)
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 codes for upper GI bleeding (example)
    (icd_version = 10 AND (
      icd_code LIKE 'K25%' OR
      icd_code LIKE 'K26%' OR
      icd_code LIKE 'K27%' OR
      icd_code LIKE 'K28%' OR
      icd_code LIKE 'K92.0%' OR
      icd_code LIKE 'K92.1%' OR
      icd_code LIKE 'K92.2%'
    ))
    -- ICD-9 codes for upper GI bleeding (example)
    OR (icd_version = 9 AND (
      icd_code LIKE '531%' OR
      icd_code LIKE '532%' OR
      icd_code LIKE '533%' OR
      icd_code LIKE '534%' OR
      icd_code LIKE '578%'
    ))
),

filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
    AND d.icd_code IN (SELECT icd_code FROM upper_gi_bleeding_codes)
    -- Primary diagnosis (lowest seq_num)
    AND d.seq_num = 1
)

SELECT
  STDDEV(los_days) AS sd_los_days
FROM
  filtered_admissions;