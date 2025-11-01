WITH
-- Identify ischemic stroke per admission: primary vs secondary
stroke_flags AS (
  SELECT di.hadm_id,
         MAX(CASE
               WHEN di.seq_num = 1 AND (
                    (di.icd_version = 9 AND (di.icd_code LIKE '434%' OR di.icd_code LIKE '436%'))
                    OR (di.icd_version = 10 AND (di.icd_code LIKE 'I63%'))
               ) THEN 1 ELSE 0 END) AS primary_stroke,
         MAX(CASE
               WHEN di.seq_num > 1 AND (
                    (di.icd_version = 9 AND (di.icd_code LIKE '434%' OR di.icd_code LIKE '436%'))
                    OR (di.icd_version = 10 AND (di.icd_code LIKE 'I63%'))
               ) THEN 1 ELSE 0 END) AS secondary_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  GROUP BY di.hadm_id
),

-- Base filtered population: female, 49-59, with ischemic stroke (primary or secondary)
base AS (
  SELECT p.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         p.gender,
         p.anchor_age,
         sf.primary_stroke,
         sf.secondary_stroke,
         DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS stay_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
       ON p.subject_id = a.subject_id
  LEFT JOIN stroke_flags sf ON a.hadm_id = sf.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Diagnostic/procedural events: count of diagnostic-imaging related procedures per admission
diag_procs AS (
  SELECT pi.hadm_id,
         COUNT(DISTINCT pi.icd_code) AS diag_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
       ON pi.icd_code = dip.icd_code
      AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%diagnostic%'
     OR LOWER(dip.long_title) LIKE '%imaging%'
     OR LOWER(dip.long_title) LIKE '%angiography%'
     OR LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%ct%'
     OR LOWER(dip.long_title) LIKE '%mri%'
     OR LOWER(dip.long_title) LIKE '%ecg%'
     OR LOWER(dip.long_title) LIKE '%echo%'
  GROUP BY pi.hadm_id
)

-- Assemble per-admission rows with stroke type and stay group
SELECT
  stroke_type,
  stay_group,
  AVG(diag_proc_count) AS mean_diag_procs_per_admission,
  MIN(diag_proc_count) AS min_diag_procs_per_admission,
  MAX(diag_proc_count) AS max_diag_procs_per_admission
FROM (
  SELECT
    CASE WHEN base.primary_stroke = 1 THEN 'primary'
         WHEN base.secondary_stroke = 1 THEN 'secondary'
    END AS stroke_type,
    CASE WHEN base.stay_days BETWEEN 1 AND 4 THEN '1-4'
         WHEN base.stay_days BETWEEN 5 AND 8 THEN '5-8'
         ELSE NULL
    END AS stay_group,
    COALESCE(dp.diag_proc_count, 0) AS diag_proc_count
  FROM base
  LEFT JOIN diag_procs dp ON base.hadm_id = dp.hadm_id
  WHERE (base.primary_stroke = 1 OR base.secondary_stroke = 1)
    AND base.stay_days BETWEEN 1 AND 8
) t
WHERE stroke_type IS NOT NULL AND stay_group IS NOT NULL
GROUP BY stroke_type, stay_group
ORDER BY stroke_type, stay_group;