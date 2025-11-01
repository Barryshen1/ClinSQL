WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND (
         (diag.icd_version = 9 AND (
            diag.icd_code LIKE '410%' OR 
            diag.icd_code LIKE '411%' 
          ))
         OR
         (diag.icd_version = 10 AND (
            diag.icd_code LIKE 'I20.0%' OR
            diag.icd_code LIKE 'I21%' OR
            diag.icd_code LIKE 'I22%' OR
            diag.icd_code LIKE 'I24%'
         ))
        )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT t.subject_id, t.hadm_id,
         t.valuenum AS first_trop_val,
         t.valueuom AS first_trop_uom
  FROM troponin_labs t
  JOIN (
    SELECT hadm_id, MIN(charttime) AS first_charttime
    FROM troponin_labs
    GROUP BY hadm_id
  ) ft
    ON t.hadm_id = ft.hadm_id
   AND t.charttime = ft.first_charttime
)
SELECT
  COUNT(DISTINCT f.subject_id) AS patient_count,
  COUNT(DISTINCT f.hadm_id) AS admission_count,
  AVG(f.first_trop_val) AS mean_trop,
  STDDEV(f.first_trop_val) AS sd_trop,
  MIN(f.first_trop_val) AS min_trop,
  MAX(f.first_trop_val) AS max_trop
FROM first_trop f
JOIN acs_admissions a
  ON f.hadm_id = a.hadm_id
WHERE f.first_trop_val > 0.04
;