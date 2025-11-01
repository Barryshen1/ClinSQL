WITH pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
glucose_itemids AS (
  SELECT
    itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%glucose%'
    AND LOWER(fluid) IN ('blood', 'serum')
),
discharge_glucose AS (
  SELECT
    pa.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id
                       ORDER BY le.charttime DESC) AS rn
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.subject_id = le.subject_id
   AND pa.hadm_id    = le.hadm_id
  JOIN glucose_itemids gi
    ON le.itemid = gi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime <= pa.dischtime
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM discharge_glucose
WHERE rn = 1;