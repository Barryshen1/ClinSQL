WITH relevant_procedures AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE LOWER(long_title) LIKE '%catheter ablation%' OR LOWER(long_title) LIKE '%cardioversion%'
),
age_filtered AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
),
procedure_counts AS (
    SELECT a.hadm_id, COUNT(DISTINCT p.icd_code) AS count_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN age_filtered a ON p.hadm_id = a.hadm_id
    JOIN relevant_procedures rp ON p.icd_code = rp.icd_code AND p.icd_version = rp.icd_version
    GROUP BY a.hadm_id
)
SELECT STDDEV(count_procedures) AS sd_procedure_count
FROM procedure_counts;