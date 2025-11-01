WITH troponin_peaks AS (
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_trop
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.hadm_id IS NOT NULL
  GROUP BY
    le.hadm_id
),
acs_admissions AS (
  SELECT DISTINCT
    a.hadm_id
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
    AND p.anchor_age = 64
    AND (
      dd.icd_code LIKE 'I20%'
      OR dd.icd_code LIKE 'I21%'
      OR dd.icd_code LIKE 'I22%'
      OR dd.icd_code LIKE 'I23%'
      OR dd.icd_code LIKE 'I24%'
      OR dd.icd_code LIKE 'I25%'
    )
)
SELECT
  APPROX_QUANTILES(tp.peak_trop, 100)[OFFSET(75)] AS troponin_75th_percentile
FROM
  troponin_peaks tp
JOIN
  acs_admissions aa
  ON tp.hadm_id = aa.hadm_id;