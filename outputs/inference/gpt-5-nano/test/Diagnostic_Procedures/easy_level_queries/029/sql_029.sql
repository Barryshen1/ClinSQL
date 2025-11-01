WITH eligible_patients AS (
  -- Male patients aged 78-88 (approximate age at admission using anchor_age)
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),
pacemaker_procedures AS (
  -- Distinct pacemaker/ICD-related procedures across admissions
  SELECT DISTINCT pi.subject_id, pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
    ON di.icd_code = pi.icd_code
   AND di.icd_version = pi.icd_version
  WHERE LOWER(COALESCE(di.long_title,'')) LIKE '%pacemaker%'
     OR LOWER(COALESCE(di.long_title,'')) LIKE '%implantable cardioverter defibrillator%'
     OR LOWER(COALESCE(di.long_title,'')) LIKE '%defibrillator%'
     OR LOWER(COALESCE(di.long_title,'')) LIKE '%pacemaker insertion%'
     OR LOWER(COALESCE(di.long_title,'')) LIKE '%pacemaker replacement%'
),
pacemaker_counts AS (
  -- Count distinct pacemaker/ICD procedures per eligible patient
  SELECT ep.subject_id,
         COUNT(DISTINCT pp.icd_code) AS pacer_count
  FROM eligible_patients AS ep
  LEFT JOIN pacemaker_procedures AS pp
    ON pp.subject_id = ep.subject_id
  GROUP BY ep.subject_id
)
SELECT
  (APPROX_QUANTILES(pacer_count, 100))[OFFSET(25)] AS percentile_25
FROM pacemaker_counts;