WITH female_admissions_with_acs AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
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
    p.gender = 'F'
    AND d.icd_version = 10
    AND (
      d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I22%'
      OR d.icd_code LIKE 'I23%'
      OR d.icd_code LIKE 'I24%'
      OR d.icd_code LIKE 'I25%'
    )
),

troponin_measurements AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS nadir_trop
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    female_admissions_with_acs fa
    ON l.hadm_id = fa.hadm_id
  WHERE
    LOWER(d.label) LIKE '%troponin%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum >= 0
    AND l.charttime BETWEEN fa.admittime AND fa.dischtime
  GROUP BY
    l.hadm_id
)

SELECT
  APPROX_QUANTILES(nadir_trop, 100)[OFFSET(25)] AS troponin_25th_percentile
FROM
  troponin_measurements;