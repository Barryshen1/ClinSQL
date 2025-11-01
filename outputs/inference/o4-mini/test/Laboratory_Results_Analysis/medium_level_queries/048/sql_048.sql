WITH ami_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.subject_id = dx.subject_id
     AND adm.hadm_id    = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dxd
      ON dx.icd_code    = dxd.icd_code
     AND dx.icd_version = dxd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND dx.seq_num = 1
    AND LOWER(dxd.long_title) LIKE '%acute myocardial infarction%'
),
first_hs_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS first_hs_tnt,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%hs troponin t%'
    AND le.valuenum IS NOT NULL
),
first_hs_tnt_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    first_hs_tnt
  FROM
    first_hs_tnt
  WHERE
    rn = 1
    AND first_hs_tnt > 0.01
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    f.first_hs_tnt
  FROM
    ami_admissions AS a
    JOIN first_hs_tnt_filtered AS f
      ON a.subject_id = f.subject_id
     AND a.hadm_id    = f.hadm_id
)
SELECT
  COUNT(DISTINCT c.subject_id)                      AS patient_count,
  COUNT(DISTINCT c.hadm_id)                         AS admission_count,
  ROUND(AVG(c.first_hs_tnt), 4)                     AS mean_hs_tnt,
  (SELECT qt[OFFSET(1)]
     FROM (SELECT APPROX_QUANTILES(first_hs_tnt, 4) AS qt FROM cohort)
  )                                                 AS hs_tnt_q1,
  (SELECT qt[OFFSET(2)]
     FROM (SELECT APPROX_QUANTILES(first_hs_tnt, 4) AS qt FROM cohort)
  )                                                 AS hs_tnt_median,
  (SELECT qt[OFFSET(3)]
     FROM (SELECT APPROX_QUANTILES(first_hs_tnt, 4) AS qt FROM cohort)
  )                                                 AS hs_tnt_q3
FROM
  cohort AS c;