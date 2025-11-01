WITH dka_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 58
    AND LOWER(dd.long_title) LIKE '%ketoacidosis%'
  GROUP BY
    a.subject_id,
    a.hadm_id
),
glucose_events AS (
  SELECT
    da.hadm_id,
    le.valuenum
  FROM
    dka_admissions AS da
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON da.subject_id = le.subject_id
      AND da.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON le.itemid = li.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%glucose%'
    AND LOWER(li.category) LIKE '%chemistry%'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.hadm_id = le.hadm_id
        AND le.charttime BETWEEN a2.admittime AND a2.dischtime
    )
),
peak_glucose_per_admission AS (
  SELECT
    hadm_id,
    MAX(valuenum) AS peak_glucose
  FROM
    glucose_events
  GROUP BY
    hadm_id
)
SELECT
  APPROX_QUANTILES(peak_glucose, 2)[OFFSET(1)] AS median_peak_glucose
FROM
  peak_glucose_per_admission;