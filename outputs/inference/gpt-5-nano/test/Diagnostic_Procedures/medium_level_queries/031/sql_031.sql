WITH aki_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
              (di.icd_version = 9 AND di.icd_code LIKE '584%')
              OR
              (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
            )
    )
),
admission_groups AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    icu_use,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS stay_group
  FROM aki_admissions
  WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),
per_admission_labs AS (
  SELECT
    ag.hadm_id,
    ag.subject_id,
    ag.icu_use,
    ag.stay_group,
    COUNT(le.labevent_id) AS lab_count
  FROM admission_groups AS ag
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = ag.hadm_id
   AND le.subject_id = ag.subject_id
   AND le.charttime BETWEEN ag.admittime AND ag.dischtime
  GROUP BY
    ag.hadm_id,
    ag.subject_id,
    ag.icu_use,
    ag.stay_group
)
SELECT
  lab.icu_use AS icu_use,
  lab.stay_group,
  AVG(lab.lab_count) AS mean_noninvasive_diagnostics,
  MIN(lab.lab_count) AS min_noninvasive_diagnostics,
  MAX(lab.lab_count) AS max_noninvasive_diagnostics
FROM per_admission_labs AS lab
GROUP BY lab.icu_use, lab.stay_group
ORDER BY lab.icu_use, lab.stay_group;