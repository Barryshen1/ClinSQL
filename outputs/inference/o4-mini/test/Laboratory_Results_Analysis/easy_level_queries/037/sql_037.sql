WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY
    a.subject_id,
    a.hadm_id
),

platelet_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%platelet%'
),

peak_platelets AS (
  SELECT
    s.hadm_id,
    MAX(le.valuenum) AS peak_platelet
  FROM
    sepsis_admissions s
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON s.hadm_id = le.hadm_id
    JOIN platelet_items pi
      ON le.itemid = pi.itemid
  WHERE
    le.valuenum IS NOT NULL
  GROUP BY
    s.hadm_id
)

SELECT
  APPROX_QUANTILES(peak_platelet, 100)[OFFSET(75)] AS p75_peak_platelet
FROM
  peak_platelets;