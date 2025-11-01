WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_code LIKE '250%' AND d.icd_version = 9)
        OR (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E14%' AND d.icd_version = 10)
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_code LIKE '428%' AND d.icd_version = 9)
        OR (d.icd_code = 'I50' AND d.icd_version = 10)
    )
),

meds_first_12h AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first_12h,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%metformin%'
              OR LOWER(e.medication) LIKE '%glyburide%'
              OR LOWER(e.medication) LIKE '%glipizide%'
              OR LOWER(e.medication) LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS oral_first_12h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime <= c.admittime + INTERVAL 12 HOUR
  GROUP BY
    c.hadm_id
),

meds_last_48h AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_last_48h,
    MAX(CASE WHEN LOWER(e.medication) LIKE '%metformin%'
              OR LOWER(e.medication) LIKE '%glyburide%'
              OR LOWER(e.medication) LIKE '%glipizide%'
              OR LOWER(e.medication) LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS oral_last_48h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= GREATEST(c.admittime, c.dischtime - INTERVAL 48 HOUR)
    AND e.charttime <= c.dischtime
  GROUP BY
    c.hadm_id
),

combined AS (
  SELECT
    c.hadm_id,
    COALESCE(f.insulin_first_12h, 0) AS insulin_first_12h,
    COALESCE(f.oral_first_12h, 0) AS oral_first_12h,
    COALESCE(l.insulin_last_48h, 0) AS insulin_last_48h,
    COALESCE(l.oral_last_48h, 0) AS oral_last_48h
  FROM
    cohort c
  LEFT JOIN
    meds_first_12h f
  ON
    c.hadm_id = f.hadm_id
  LEFT JOIN
    meds_last_48h l
  ON
    c.hadm_id = l.hadm_id
)

SELECT
  ROUND(AVG(insulin_first_12h) * 100, 2) AS insulin_prev_first_12h,
  ROUND(AVG(oral_first_12h) * 100, 2) AS oral_prev_first_12h,
  ROUND(AVG(insulin_last_48h) * 100, 2) AS insulin_prev_last_48h,
  ROUND(AVG(oral_last_48h) * 100, 2) AS oral_prev_last_48h,
  ROUND((AVG(insulin_last_48h) - AVG(insulin_first_12h)) * 100, 2) AS insulin_net_change_pp,
  ROUND((AVG(oral_last_48h) - AVG(oral_first_12h)) * 100, 2) AS oral_net_change_pp
FROM
  combined;