WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
pneumonia_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN male_patients p ON d.subject_id = p.subject_id
  WHERE
    (
      (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
      OR
      (d.icd_version = 10 AND LEFT(d.icd_code, 3) BETWEEN 'J12' AND 'J18')
    )
),
discharge_times AS (
  SELECT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN pneumonia_admissions pa ON a.subject_id = pa.subject_id AND a.hadm_id = pa.hadm_id
),
serum_glucose_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%' AND LOWER(fluid) = 'serum'
),
discharge_serum_glucose AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    dt.dischtime,
    ROW_NUMBER() OVER (
      PARTITION BY l.subject_id, l.hadm_id
      ORDER BY ABS(TIMESTAMP_DIFF(dt.dischtime, l.charttime, SECOND))
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN discharge_times dt
    ON l.subject_id = dt.subject_id AND l.hadm_id = dt.hadm_id
  JOIN serum_glucose_items sgi
    ON l.itemid = sgi.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime <= dt.dischtime
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[SAFE_OFFSET(75)] AS serum_glucose_75th_percentile
FROM discharge_serum_glucose
WHERE rn = 1;