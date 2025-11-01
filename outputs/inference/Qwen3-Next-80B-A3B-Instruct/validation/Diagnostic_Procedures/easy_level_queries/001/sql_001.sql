WITH cardiac_procedures AS (
  SELECT DISTINCT
    p.hadm_id,
    p.icd_code
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac%'
     OR LOWER(d.long_title) LIKE '%heart%'
     OR LOWER(d.long_title) LIKE '%coronary%'
     OR LOWER(d.long_title) LIKE '%bypass%'
     OR LOWER(d.long_title) LIKE '%angioplasty%'
     OR LOWER(d.long_title) LIKE '%valve%'
     OR LOWER(d.long_title) LIKE '%myocardial%'
     OR LOWER(d.long_title) LIKE '%stent%'
     OR LOWER(d.long_title) LIKE '%pacemaker%'
     OR LOWER(d.long_title) LIKE '%defibrillator%'
     OR LOWER(d.long_title) LIKE '%catheter%'
     OR LOWER(d.long_title) LIKE '%endarterectomy%'
     OR LOWER(d.long_title) LIKE '%aortic%'
     OR LOWER(d.long_title) LIKE '%pericardial%'
     OR LOWER(d.long_title) LIKE '%cardiopulmonary%'
),
filtered_patients AS (
  SELECT
    subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
),
procedures_per_admission AS (
  SELECT
    cp.hadm_id,
    COUNT(DISTINCT cp.icd_code) AS distinct_cardiac_procedures
  FROM cardiac_procedures cp
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON cp.hadm_id = a.hadm_id
  INNER JOIN filtered_patients fp
    ON a.subject_id = fp.subject_id
  GROUP BY cp.hadm_id
)
SELECT
  PERCENTILE_DISC(distinct_cardiac_procedures, 0.75) AS p75_distinct_cardiac_procedures
FROM procedures_per_admission;