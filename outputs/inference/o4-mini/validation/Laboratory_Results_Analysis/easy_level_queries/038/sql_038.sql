WITH stroke_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code
     AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND LOWER(di.long_title) LIKE '%ischemic stroke%'
),

hemoglobin_events AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    le.valuenum,
    le.charttime AS chart_dt
  FROM
    stroke_admissions AS sa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON sa.subject_id = le.subject_id
     AND sa.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON le.itemid = li.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN sa.admittime
                       AND DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
    AND LOWER(li.label) LIKE '%hemoglobin%'
)

SELECT
  he.subject_id,
  he.hadm_id,
  MIN(he.valuenum) AS min_hemoglobin_first_24h
FROM
  hemoglobin_events AS he
GROUP BY
  he.subject_id,
  he.hadm_id
ORDER BY
  min_hemoglobin_first_24h ASC;