WITH male_pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code BETWEEN '480' AND '486')
      OR (diag.icd_version = 10 AND diag.icd_code BETWEEN 'J12' AND 'J18')
    )
),
glucose_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(dl.label) LIKE '%glucose%'
    AND LOWER(dl.fluid) IN ('blood', 'serum', 'plasma') -- common fluids for serum glucose
)
, last_glucose_per_adm AS (
  SELECT mpa.subject_id, mpa.hadm_id, gl.valuenum
  FROM male_pneumonia_admissions mpa
  JOIN glucose_labs gl
    ON mpa.subject_id = gl.subject_id
   AND mpa.hadm_id = gl.hadm_id
   AND gl.charttime <= mpa.dischtime
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY mpa.subject_id, mpa.hadm_id
    ORDER BY gl.charttime DESC
  ) = 1
)
SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS pct75_glucose_at_discharge
FROM last_glucose_per_adm;