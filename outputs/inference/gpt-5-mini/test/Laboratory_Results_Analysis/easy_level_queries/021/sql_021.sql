WITH pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  USING (subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
    AND di.icd_version = dic.icd_version
  WHERE
    LOWER(p.gender) = 'm'
    AND LOWER(dic.long_title) LIKE '%pneumonia%'
),

last_serum_glucose AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.dischtime,
    le.valuenum AS glucose_val,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY le.charttime DESC) AS rn
  FROM
    pneumonia_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = pa.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON li.itemid = le.itemid
  WHERE
    le.charttime <= pa.dischtime
    AND le.valuenum IS NOT NULL
    -- require glucose in label
    AND LOWER(li.label) LIKE '%glucose%'
    -- exclude urine glucose tests
    AND LOWER(li.label) NOT LIKE '%urine%'
    -- favor serum/plasma/blood specimens or explicit serum/plasma in label
    AND (
      COALESCE(LOWER(li.fluid), '') LIKE '%ser%' OR
      COALESCE(LOWER(li.fluid), '') LIKE '%plas%' OR
      COALESCE(LOWER(li.fluid), '') LIKE '%blood%' OR
      LOWER(li.label) LIKE '%serum%' OR
      LOWER(li.label) LIKE '%plasma%'
    )
)

SELECT
  -- approximate 75th percentile (approximate quantiles 0..100; OFFSET(75) = 75th percentile)
  APPROX_QUANTILES(glucose_val, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM (
  SELECT
    hadm_id,
    glucose_val
  FROM
    last_serum_glucose
  WHERE rn = 1
)
;