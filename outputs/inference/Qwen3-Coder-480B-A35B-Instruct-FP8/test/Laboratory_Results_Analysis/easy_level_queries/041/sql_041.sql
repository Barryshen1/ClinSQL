WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
creatinine_first_24h AS (
  SELECT
    l.hadm_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    pneumonia_admissions pa
    ON l.hadm_id = pa.hadm_id
  WHERE
    LOWER(d.label) = 'creatinine'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    l.hadm_id
)
SELECT
  STDDEV(avg_creatinine) AS stddev_creatinine
FROM
  creatinine_first_24h;