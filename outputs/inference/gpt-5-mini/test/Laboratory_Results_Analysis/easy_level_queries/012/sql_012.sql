SELECT
  COUNT(*) AS n_platelet_measurements_on_discharge_day,
  APPROX_QUANTILES(l.valuenum, 100)[SAFE_OFFSET(75)] AS platelet_p75
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` ad
  ON p.subject_id = ad.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON ad.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
  ON di.icd_code = ddesc.icd_code
  AND di.icd_version = ddesc.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON l.hadm_id = ad.hadm_id
  AND l.subject_id = ad.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` li
  ON l.itemid = li.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age = 87
  -- diagnosis text match for hemorrhagic stroke (covers common ICD descriptions)
  AND (
    LOWER(COALESCE(ddesc.long_title, '')) LIKE '%hemorrhag%'     -- catches 'hemorrhage', 'hemorrhagic', etc.
    OR LOWER(COALESCE(ddesc.long_title, '')) LIKE '%intracerebral%'
    OR LOWER(COALESCE(ddesc.long_title, '')) LIKE '%subarachnoid%'
    OR LOWER(COALESCE(ddesc.long_title, '')) LIKE '%intracranial%'
  )
  -- platelet lab tests
  AND LOWER(COALESCE(li.label, '')) LIKE '%platelet%'
  -- measurement on the discharge day
  AND DATE(l.charttime) = DATE(ad.dischtime)
  -- numeric result
  AND l.valuenum IS NOT NULL;