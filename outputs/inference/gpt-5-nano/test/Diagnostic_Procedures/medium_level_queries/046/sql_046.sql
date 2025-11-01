WITH target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- approximate age at admission
    (CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) BETWEEN 50 AND 60
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
              (di.icd_version = 9 AND di.icd_code LIKE '435%')
              OR
              (di.icd_version = 10 AND di.icd_code LIKE 'G45%')
            )
    )
),
ctmri_by_hadm AS (
  SELECT
    icu.hadm_id,
    COUNT(*) AS ctmri_cnt
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON pe.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%mri%')
    -- ensure the procedure happened during the ICU stay
    AND pe.starttime BETWEEN icu.intime AND icu.outtime
  GROUP BY icu.hadm_id
)

SELECT
  los_group AS los_group,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(c.ctmri_cnt, 0)) AS mean_ct_mri_per_admission
FROM (
  SELECT
    ta.subject_id,
    ta.hadm_id,
    CASE
      WHEN TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM target_admissions AS ta
  WHERE TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) BETWEEN 1 AND 7
) AS a
LEFT JOIN ctmri_by_hadm AS c ON a.hadm_id = c.hadm_id
WHERE a.los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;