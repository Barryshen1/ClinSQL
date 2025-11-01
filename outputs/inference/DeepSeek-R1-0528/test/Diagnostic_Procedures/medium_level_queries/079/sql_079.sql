WITH lgib_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age,
    -- Flag primary LGIB (seq_num=1) and secondary (seq_num>1 with no primary)
    MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_lgib,
    MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_lgib
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND d.icd_code IN ('5780','5781','5789','56985','K625','K922') 
    AND d.icd_version IN (9,10)
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age, p.anchor_year
  HAVING has_primary_lgib = 1 OR has_secondary_lgib = 1
),
filtered_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    admission_age,
    -- Define diagnosis group: Primary if exists, else Secondary
    CASE 
      WHEN has_primary_lgib = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_group,
    -- Calculate LOS in days
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM lgib_admissions
  WHERE admission_age BETWEEN 71 AND 81
),
imaging_codes AS (
  -- ICD procedure codes for CT/radiography
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'computed tomography|ct scan|radiography')
  UNION ALL
  -- HCPCS codes for CT/radiography
  SELECT code AS icd_code, 
         NULL AS icd_version  -- Placeholder for HCPCS (no version)
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    REGEXP_CONTAINS(LOWER(short_description), r'computed tomography|ct scan|radiography') OR
    REGEXP_CONTAINS(LOWER(long_description), r'computed tomography|ct scan|radiography')
),
imaging_events AS (
  -- Procedures from procedures_icd
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN imaging_codes c
    ON p.icd_code = c.icd_code 
    AND (p.icd_version = c.icd_version OR c.icd_version IS NULL)  -- Handle HCPCS placeholder
  UNION ALL
  -- Procedures from hcpcsevents
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN imaging_codes c
    ON h.hcpcs_cd = c.icd_code
),
imaging_counts AS (
  SELECT hadm_id, COUNT(*) AS imaging_count
  FROM imaging_events
  GROUP BY hadm_id
),
final_admissions AS (
  SELECT 
    a.hadm_id,
    a.diagnosis_group,
    a.los_days,
    COALESCE(i.imaging_count, 0) AS imaging_count  -- Include admissions with 0 imaging
  FROM filtered_admissions a
  LEFT JOIN imaging_counts i
    ON a.hadm_id = i.hadm_id
  WHERE a.los_days BETWEEN 1 AND 7  -- Only 1-7 day stays
)
SELECT 
  diagnosis_group,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(imaging_count) AS mean_imaging_procedures
FROM final_admissions
GROUP BY diagnosis_group, los_group
ORDER BY diagnosis_group, los_group;