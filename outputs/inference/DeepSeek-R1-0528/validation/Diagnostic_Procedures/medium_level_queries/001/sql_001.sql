WITH acs_admissions AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.gender,
      (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE 
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 77 AND 87
),
acs_diagnoses AS (
  SELECT 
      subject_id, 
      hadm_id, 
      seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
      (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '411%'))
      OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'I20.0'))
),
admission_acs_priority AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.age_admit,
      MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary,
      MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) AS is_secondary
  FROM acs_admissions a
  INNER JOIN acs_diagnoses d
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  GROUP BY a.subject_id, a.hadm_id, a.age_admit
),
icu_stays AS (
  SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id,
      i.intime, 
      i.outtime, 
      i.los,
      CASE 
          WHEN i.los BETWEEN 1 AND 4 THEN '1-4'
          WHEN i.los BETWEEN 5 AND 8 THEN '5-8'
      END AS los_group,
      CASE 
          WHEN a.is_primary = 1 THEN 'Primary'
          WHEN a.is_secondary = 1 THEN 'Secondary'
      END AS diag_priority
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN admission_acs_priority a
      ON i.hadm_id = a.hadm_id AND i.subject_id = a.subject_id
  WHERE i.los BETWEEN 1 AND 8
),
radiology_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
      LOWER(long_description) LIKE '%radiograph%' 
      OR LOWER(long_description) LIKE '%x-ray%' 
      OR LOWER(long_description) LIKE '%computed tomography%' 
      OR LOWER(long_description) LIKE '%ct scan%' 
      OR LOWER(long_description) LIKE '%tomogram%'
),
procedure_events AS (
  SELECT 
      icu.stay_id,
      icu.los_group,
      icu.diag_priority,
      COUNT(*) AS procedure_count  -- Fixed: Replaced invalid column with COUNT(*)
  FROM icu_stays icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      ON icu.hadm_id = hc.hadm_id
      AND DATE(hc.chartdate) BETWEEN DATE(icu.intime) AND DATE(icu.outtime)
  LEFT JOIN radiology_codes rc
      ON hc.hcpcs_cd = rc.code
  WHERE rc.code IS NOT NULL  -- Only count radiology procedures
  GROUP BY icu.stay_id, icu.los_group, icu.diag_priority
)
SELECT 
    los_group,
    diag_priority,
    AVG(procedure_count) AS mean_count,
    MIN(procedure_count) AS min_count,
    MAX(procedure_count) AS max_count
FROM procedure_events
GROUP BY los_group, diag_priority
ORDER BY los_group, diag_priority;