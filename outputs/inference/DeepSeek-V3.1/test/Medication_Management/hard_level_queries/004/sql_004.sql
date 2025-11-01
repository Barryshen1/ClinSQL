WITH base_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        pat.anchor_age,
        drg.drg_severity,
        -- Calculate LOS in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
        ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
        ON adm.hadm_id = drg.hadm_id AND drg.drg_type = 'APR'
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 48 AND 58
        AND diag.icd_code LIKE 'I63%'
        AND diag.icd_version = 10
),
-- Define exposure: has CYP3A4 interaction affecting NTI drugs
exposure_flag AS (
    SELECT 
        bc.subject_id,
        bc.hadm_id,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p1
                WHERE bc.hadm_id = p1.hadm_id
                AND (
                    LOWER(p1.drug) LIKE '%warfarin%' OR
                    LOWER(p1.drug) LIKE '%phenytoin%' OR
                    LOWER(p1.drug) LIKE '%carbamazepine%' OR
                    LOWER(p1.drug) LIKE '%digoxin%' OR
                    LOWER(p1.drug) LIKE '%lithium%' OR
                    LOWER(p1.drug) LIKE '%theophylline%' OR
                    LOWER(p1.drug) LIKE '%cyclosporine%' OR
                    LOWER(p1.drug) LIKE '%tacrolimus%' OR
                    LOWER(p1.drug) LIKE '%sirolimus%'
                )
            )
            AND EXISTS (
                SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p2
                WHERE bc.hadm_id = p2.hadm_id
                AND (
                    LOWER(p2.drug) LIKE '%ketoconazole%' OR
                    LOWER(p2.drug) LIKE '%itraconazole%' OR
                    LOWER(p2.drug) LIKE '%voriconazole%' OR
                    LOWER(p2.drug) LIKE '%clarithromycin%' OR
                    LOWER(p2.drug) LIKE '%erythromycin%' OR
                    LOWER(p2.drug) LIKE '%diltiazem%' OR
                    LOWER(p2.drug) LIKE '%verapamil%' OR
                    LOWER(p2.drug) LIKE '%fluconazole%' OR
                    LOWER(p2.drug) LIKE '%cimetidine%' OR
                    LOWER(p2.drug) LIKE '%rifampin%' OR
                    LOWER(p2.drug) LIKE '%rifabutin%' OR
                    LOWER(p2.drug) LIKE '%phenobarbital%'
                    -- Note: removed phenytoin and carbamazepine from this list to avoid overlap
                )
            )
            THEN 1
            ELSE 0
        END AS has_exposure
    FROM base_cohort bc
),
-- Combine base cohort with exposure flag
cohort_with_exposure AS (
    SELECT 
        bc.*,
        ef.has_exposure
    FROM base_cohort bc
    LEFT JOIN exposure_flag ef
        ON bc.hadm_id = ef.hadm_id
),
-- For part1: compare exposed vs control
part1_results AS (
    SELECT 
        has_exposure,
        COUNT(*) AS n_patients,
        AVG(drg_severity) AS avg_complexity,
        COUNTIF(drg_severity = 1) AS severity_1,
        COUNTIF(drg_severity = 2) AS severity_2,
        COUNTIF(drg_severity = 3) AS severity_3,
        COUNTIF(drg_severity = 4) AS severity_4,
        AVG(los_days) AS avg_los,
        SUM(hospital_expire_flag) AS deaths,
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
    FROM cohort_with_exposure
    GROUP BY has_exposure
),
-- For part2: top quartile (severity=4) patients
part2_results AS (
    SELECT 
        'Top Quartile' AS cohort,
        COUNT(*) AS n_patients,
        AVG(los_days) AS avg_los,
        SUM(hospital_expire_flag) AS deaths,
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
    FROM cohort_with_exposure
    WHERE drg_severity = 4
)
-- Final output
SELECT 
    'Part1: Exposed vs Control' AS analysis,
    has_exposure,
    n_patients,
    avg_complexity,
    severity_1,
    severity_2,
    severity_3,
    severity_4,
    avg_los,
    deaths,
    mortality_rate
FROM part1_results
UNION ALL
SELECT 
    'Part2: Top Quartile' AS analysis,
    NULL AS has_exposure,
    n_patients,
    NULL AS avg_complexity,
    NULL AS severity_1,
    NULL AS severity_2,
    NULL AS severity_3,
    NULL AS severity_4,
    avg_los,
    deaths,
    mortality_rate
FROM part2_results;