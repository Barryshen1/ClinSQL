WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND did.long_title LIKE '%COPD%'
),

creatnine_first_24h AS (
  SELECT
    l.hadm_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    cohort c
    ON l.hadm_id = c.hadm_id
  WHERE
    LOWER(d.label) = 'creatinine'
    AND LOWER(d.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    l.hadm_id
)

SELECT
  APPROX_QUANTILES(avg_creatinine, 100)[OFFSET(75)] AS percentile_75_avg_creatinine
FROM
  creatnine_first_24h;