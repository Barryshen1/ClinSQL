WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
      USING (icd_code, icd_version)
      WHERE
        di.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%pneumonia%'
    )
),

per_admission_creat AS (
  SELECT
    c.hadm_id,
    AVG(le.valuenum) AS avg_creat_first_24h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    le.hadm_id = c.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
  ON
    le.itemid = li.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%creatinine%'
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.hadm_id
)

SELECT
  STDDEV_SAMP(avg_creat_first_24h) AS sd_of_avg_creatinine_mg_dL,
  COUNT(*) AS n_admissions_used
FROM
  per_admission_creat;