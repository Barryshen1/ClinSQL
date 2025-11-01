WITH proc_icd AS (
  SELECT pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE 
    (d.long_title LIKE '%ablation%' AND (d.long_title LIKE '%heart%' OR d.long_title LIKE '%cardiac%'))
    OR d.long_title LIKE '%cardioversion%'
),
proc_hcpcs AS (
  SELECT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE 
    (d.long_description LIKE '%ablation%' AND (d.long_description LIKE '%heart%' OR d.long_description LIKE '%cardiac%'))
    OR d.long_description LIKE '%cardioversion%'
),
proc_icu AS (
  SELECT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON pe.itemid = d.itemid
  WHERE d.label LIKE '%cardioversion%'
),
all_procs AS (
  SELECT hadm_id FROM proc_icd
  UNION ALL
  SELECT hadm_id FROM proc_hcpcs
  UNION ALL
  SELECT hadm_id FROM proc_icu
),
eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admityear
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_admissions AS (
  SELECT 
    subject_id,
    hadm_id
  FROM eligible_admissions
  WHERE anchor_age + (admityear - anchor_year) BETWEEN 86 AND 96
),
patient_proc_counts AS (
  SELECT 
    fa.subject_id,
    COUNT(ap.hadm_id) AS proc_count
  FROM filtered_admissions fa
  LEFT JOIN all_procs ap
    ON fa.hadm_id = ap.hadm_id
  GROUP BY fa.subject_id
)
SELECT STDDEV(proc_count) AS sd_procedures
FROM patient_proc_counts;