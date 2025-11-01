WITH hhs_cohort AS (
  -- Select male patients aged 58-68 with Hyperosmolar Hyperglycemic State (HHS)
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (UPPER(d.long_title) LIKE '%HYPEROSMOLAR%')
),
admissions_los AS (
  SELECT subject_id, hadm_id, los_days, los_group
  FROM hhs_cohort
  WHERE los_group IS NOT NULL
),
radiology_by_adm AS (
  -- Count radiology/CT procedures per admission, via ICU procedure events
  SELECT i.hadm_id,
         COUNT(*) AS radiology_count
  FROM admissions_los al
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = al.subject_id AND i.hadm_id = al.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.subject_id = i.subject_id AND pe.hadm_id = i.hadm_id AND pe.stay_id = i.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di_item
    ON pe.itemid = di_item.itemid
  WHERE
    di_item IS NOT NULL
    AND (UPPER(di_item.category) LIKE '%RADIOL%' OR UPPER(di_item.label) LIKE '%CT%' OR UPPER(di_item.label) LIKE '%RADIOGRAPHY%')
  GROUP BY i.hadm_id
)
SELECT
  al.los_group,
  COUNT(DISTINCT al.subject_id) AS patient_count,
  COUNT(DISTINCT al.hadm_id) AS admission_count,
  SAFE_DIVIDE(SUM(COALESCE(radiology_by_adm.radiology_count, 0)),
              COUNT(DISTINCT al.hadm_id)) AS mean_radiology_per_admission
FROM admissions_los AS al
LEFT JOIN radiology_by_adm
  ON al.hadm_id = radiology_by_adm.hadm_id
GROUP BY al.los_group
ORDER BY al.los_group;