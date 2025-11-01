WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND dx.seq_num = 1
    AND (
      LOWER(d.long_title) LIKE '%chest pain%'
      OR LOWER(d.long_title) LIKE '%acute myocardial infarction%'
    )
),
troponin_first AS (
  SELECT
    l.hadm_id,
    MIN(l.charttime) AS first_trop_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
  GROUP BY
    l.hadm_id
),
troponin_values AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    troponin_first t
  ON
    l.hadm_id = t.hadm_id
    AND l.charttime = t.first_trop_time
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum > 0.04
)
SELECT
  COUNT(*) AS total_patients,
  SUM(c.hospital_expire_flag) AS deaths,
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM
  cohort c
JOIN
  troponin_values t
ON
  c.hadm_id = t.hadm_id;