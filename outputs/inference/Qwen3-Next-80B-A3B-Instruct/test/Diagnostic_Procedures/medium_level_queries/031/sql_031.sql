WITH aki_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      did.icd_code LIKE 'N17%' 
      OR did.icd_code LIKE 'N16%'
    )
),

icu_stay_duration AS (
  SELECT
    hadm_id,
    SUM(los) AS total_los_days
  FROM physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY hadm_id
  HAVING SUM(los) >= 1 AND SUM(los) <= 7
),

non_invasive_diagnostics AS (
  SELECT
    pe.hadm_id,
    COUNT(*) AS non_invasive_diag_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  WHERE di.linksto = 'procedureevents'
    AND (
      UPPER(di.label) LIKE '%CT%' 
      OR UPPER(di.label) LIKE '%CAT SCAN%' 
      OR UPPER(di.label) LIKE '%COMPUTED TOMOGRAPHY%'
      OR UPPER(di.label) LIKE '%ULTRASOUND%'
      OR UPPER(di.label) LIKE '%US%'
      OR UPPER(di.label) LIKE '%ECHO%'
      OR UPPER(di.label) LIKE '%ECHOCARDIOGRAM%'
      OR UPPER(di.label) LIKE '%X-RAY%'
      OR UPPER(di.label) LIKE '%XRAY%'
      OR UPPER(di.label) LIKE '%RAD%'
      OR UPPER(di.label) LIKE '%RADIOGRAPH%'
      OR UPPER(di.label) LIKE '%MRI%'
      OR UPPER(di.label) LIKE '%MAGNETIC RESONANCE%'
      OR UPPER(di.label) LIKE '%ECG%'
      OR UPPER(di.label) LIKE '%EKG%'
    )
    AND NOT (
      UPPER(di.label) LIKE '%CATH%' 
      OR UPPER(di.label) LIKE '%INSERTION%' 
      OR UPPER(di.label) LIKE '%TUBE%' 
      OR UPPER(di.label) LIKE '%DIALYSIS%' 
      OR UPPER(di.label) LIKE '%INTUBATION%' 
      OR UPPER(di.label) LIKE '%VENTILATION%' 
      OR UPPER(di.label) LIKE '%CENTRAL%' 
      OR UPPER(di.label) LIKE '%LINES%' 
      OR UPPER(di.label) LIKE '%BIOPSY%' 
      OR UPPER(di.label) LIKE '%LUMBAR%' 
      OR UPPER(di.label) LIKE '%NEURO%' 
      OR UPPER(di.label) LIKE '%SURGICAL%'
    )
  GROUP BY pe.hadm_id
)

SELECT
  CASE 
    WHEN isd.total_los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN isd.total_los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS icu_stay_group,
  AVG(nid.non_invasive_diag_count) AS mean_non_invasive_diagnostics,
  MIN(nid.non_invasive_diag_count) AS min_non_invasive_diagnostics,
  MAX(nid.non_invasive_diag_count) AS max_non_invasive_diagnostics
FROM aki_admissions aa
JOIN icu_stay_duration isd ON aa.hadm_id = isd.hadm_id
LEFT JOIN non_invasive_diagnostics nid ON aa.hadm_id = nid.hadm_id
GROUP BY icu_stay_group
ORDER BY icu_stay_group;