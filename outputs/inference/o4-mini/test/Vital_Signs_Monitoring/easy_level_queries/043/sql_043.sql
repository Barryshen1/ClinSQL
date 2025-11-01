WITH gcs_item AS (
  -- Identify the GCS Total itemid in ICU chart events
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%glasgow coma scale total%'
),
first_gcs AS (
  -- For each ICU stay, pick the first GCS Total measurement
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS gcs_total,
    ce.charttime,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN gcs_item gi
      ON ce.itemid = gi.itemid
  WHERE
    ce.valuenum IS NOT NULL
)
SELECT
  AVG(fg.gcs_total) AS avg_first_gcs_total
FROM
  first_gcs fg
  -- only keep the first measurement per stay
  JOIN (
    SELECT stay_id
    FROM first_gcs
    WHERE rn = 1
  ) fg1
    ON fg.stay_id = fg1.stay_id
  -- join to ICU stays and admissions and patients
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON fg.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
WHERE
  -- Male patients age 77–87
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 77 AND 87;