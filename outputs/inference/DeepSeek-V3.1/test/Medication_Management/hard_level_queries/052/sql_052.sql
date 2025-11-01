WITH all_inpatients AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        pt.anchor_age, 
        pt.gender, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
),

hhs_patients AS (
    SELECT 
        diag.subject_id,
        diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE 
        (diag.icd_version = 9 AND diag.icd_code LIKE '250.2%') OR (diag.icd_version = 10 AND diag.icd_code IN ('E11.00', 'E13.00'))
),

target_cohort AS (
    SELECT 
        ai.*
    FROM all_inpatients ai
    INNER JOIN hhs_patients hhs
        ON ai.hadm_id = hhs.hadm_id
    WHERE 
        ai.gender = 'F' 
        AND ai.anchor_age BETWEEN 68 AND 78
),

medications_72hr AS (
    SELECT 
        pr.subject_id,
        pr.hadm_id,
        COUNT(DISTINCT pr.drug) AS num_drugs
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN target_cohort tc
        ON pr.hadm_id = tc.hadm_id
    WHERE 
        DATETIME_DIFF(pr.starttime, tc.admittime, HOUR) <= 72
    GROUP BY pr.subject_id, pr.hadm_id
),

hyperkalemia_drugs AS (
    SELECT 
        pr.subject_id,
        pr.hadm_id,
        COUNT(*) AS hyperkalemia_drug_count
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN all_inpatients ai
        ON pr.hadm_id = ai.hadm_id
    WHERE 
        DATETIME_DIFF(pr.starttime, ai.admittime, HOUR) <= 72
        AND (
            LOWER(pr.drug) LIKE '%potassium%' OR
            LOWER(pr.drug) LIKE '%spironolactone%' OR
            LOWER(pr.drug) LIKE '%triamterene%' OR
            LOWER(pr.drug) LIKE '%amiloride%' OR
            LOWER(pr.drug) LIKE '%eplerenone%' OR
            LOWER(pr.drug) LIKE '%ace inhibitor%' OR
            LOWER(pr.drug) LIKE '%arb%' OR
            LOWER(pr.drug) LIKE '%losartan%' OR
            LOWER(pr.drug) LIKE '%valsartan%' OR
            LOWER(pr.drug) LIKE '%irbesartan%' OR
            LOWER(pr.drug) LIKE '%candesartan%' OR
            LOWER(pr.drug) LIKE '%olmesartan%' OR
            LOWER(pr.drug) LIKE '%telmisartan%' OR
            LOWER(pr.drug) LIKE '%benazepril%' OR
            LOWER(pr.drug) LIKE '%captopril%' OR
            LOWER(pr.drug) LIKE '%enalapril%' OR
            LOWER(pr.drug) LIKE '%fosinopril%' OR
            LOWER(pr.drug) LIKE '%lisinopril%' OR
            LOWER(pr.drug) LIKE '%moexipril%' OR
            LOWER(pr.drug) LIKE '%perindopril%' OR
            LOWER(pr.drug) LIKE '%quinapril%' OR
            LOWER(pr.drug) LIKE '%ramipril%' OR
            LOWER(pr.drug) LIKE '%trandolapril%' OR
            LOWER(pr.drug) LIKE '%trimethoprim%' OR
            LOWER(pr.drug) LIKE '%heparin%' OR
            LOWER(pr.drug) LIKE '%cyclosporine%' OR LOWER(pr.drug) LIKE '%tacrolimus%'
        )
    GROUP BY pr.subject_id, pr.hadm_id
),

hyperkalemia_all AS (
    SELECT 
        ai.subject_id,
        ai.hadm_id,
        COALESCE(hd.hyperkalemia_drug_count, 0) AS hyperkalemia_drug_count
    FROM all_inpatients ai
    LEFT JOIN hyperkalemia_drugs hd
        ON ai.hadm_id = hd.hadm_id
),

target_hyperkalemia AS (
    SELECT 
        tc.subject_id,
        tc.hadm_id,
        COALESCE(hd.hyperkalemia_drug_count, 0) AS hyperkalemia_drug_count
    FROM target_cohort tc
    LEFT JOIN hyperkalemia_drugs hd
        ON tc.hadm_id = hd.hadm_id
),

percentile_ranks AS (
    SELECT 
        th.subject_id,
        th.hadm_id,
        PERCENT_RANK() OVER (ORDER BY ha.hyperkalemia_drug_count) AS percentile_rank
    FROM target_hyperkalemia th
    CROSS JOIN hyperkalemia_all ha
),

aggregates AS (
    SELECT
        (SELECT APPROX_QUANTILES(num_drugs, 100) FROM medications_72hr) AS med_complexity_distribution,
        APPROX_QUANTILES(pr.percentile_rank, 100)[OFFSET(50)] AS median_percentile_rank,
        (SELECT COUNT(*) FROM target_hyperkalemia WHERE hyperkalemia_drug_count > 0) * 100.0 / (SELECT COUNT(*) FROM target_cohort) AS percent_affected,
        APPROX_QUANTILES(tc.los_days, 4)[OFFSET(3)] AS top_quartile_los,
        (SELECT COUNT(*) FROM target_cohort WHERE hospital_expire_flag = 1) * 100.0 / (SELECT COUNT(*) FROM target_cohort) AS mortality_rate
    FROM percentile_ranks pr
    CROSS JOIN target_cohort tc
    LIMIT 1
)

SELECT * FROM aggregates;