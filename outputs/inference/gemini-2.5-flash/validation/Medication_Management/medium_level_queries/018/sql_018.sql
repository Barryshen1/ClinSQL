WITH cohort_admissions AS (
            SELECT
                ad.subject_id,
                ad.hadm_id,
                ad.admittime,
                ad.dischtime,
                -- Calculate age at admission. Mimic-IV anchor_year_group simplifies age calculation and prevents re-identifcation.
                pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) AS age_at_admission,
                pa.gender
            FROM
                `physionet-data.mimiciv_3_1_hosp.admissions` ad
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.patients` pa
                ON ad.subject_id = pa.subject_id
            WHERE
                ad.dischtime IS NOT NULL -- Ensure only completed hospital admissions are considered for final 48h calculation
        ),
        -- Patients with Type 2 Diabetes Mellitus
        cohort_t2dm AS (
            SELECT DISTINCT di.hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
                ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
            WHERE
                (di.icd_version = 10 AND di.icd_code LIKE 'E11%') -- ICD-10 Type 2 Diabetes Mellitus
                OR
                (di.icd_version = 9 AND di.icd_code LIKE '250%' AND did.long_title LIKE '%Type 2%' AND did.long_title NOT LIKE '%Type 1%') -- ICD-9, ensuring Type 2 and not Type 1; Note: a more robust ICD-9 T2DM identification might involve excluding specific codes for secondary DM or other types. This uses the existing logic.
        ),
        -- Patients with Heart Failure
        cohort_heart_failure AS (
            SELECT DISTINCT di.hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 Heart failure
                OR
                (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 Heart failure
        ),
        -- Final cohort of patients meeting all demographic and diagnostic criteria (admission-level)
        final_cohort AS (
            SELECT
                ca.subject_id,
                ca.hadm_id,
                ca.admittime,
                ca.dischtime
            FROM
                cohort_admissions ca
            WHERE
                ca.gender = 'F'
                AND ca.age_at_admission BETWEEN 81 AND 91
                AND ca.hadm_id IN (SELECT hadm_id FROM cohort_t2dm)
                AND ca.hadm_id IN (SELECT hadm_id FROM cohort_heart_failure)
        ),
        -- Total number of unique admissions in the final cohort (denominator for prevalence)
        num_cohort_admissions AS (
            SELECT COUNT(hadm_id) AS total_admissions
            FROM final_cohort
        ),
        -- Define oral antidiabetic drug classes and their keywords
        drug_keywords AS (
            SELECT 'Metformin' AS drug_class, ['metformin'] AS keywords UNION ALL
            SELECT 'Sulfonylurea', ['glipizide', 'glyburide', 'glimepiride', 'glyburide-metformin'] UNION ALL
            SELECT 'DPP4', ['sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin', 'vildagliptin'] UNION ALL
            SELECT 'SGLT2', ['canagliflozin', 'dapagliflozin', 'empagliflozin', 'ertugliflozin'] UNION ALL
            SELECT 'TZD', ['pioglitazone', 'rosiglitazone']
        ),
        -- Flatten drug_keywords into a table where each row is a drug_class and a single keyword
        drug_keywords_exploded AS (
            SELECT
                dk.drug_class,
                keyword
            FROM
                drug_keywords dk,
                UNNEST(dk.keywords) AS keyword
        ),
        -- Identify distinct patient-hadm_id-drug_class exposures within each time window
        patient_drug_exposure AS (
            SELECT
                fc.subject_id,
                fc.hadm_id,
                dke.drug_class, -- Use drug_class from the exploded table
                -- Flag if the drug was prescribed in the first 72 hours of admission
                MAX(CASE WHEN p.starttime >= fc.admittime AND p.starttime <= DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS exposed_first_72h,
                -- Flag if the drug was prescribed in the final 48 hours before discharge
                MAX(CASE WHEN p.starttime >= DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND p.starttime <= fc.dischtime THEN 1 ELSE 0 END) AS exposed_final_48h
            FROM
                final_cohort fc
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.prescriptions` p
                ON fc.subject_id = p.subject_id AND fc.hadm_id = p.hadm_id
            INNER JOIN
                drug_keywords_exploded dke -- Join with the flattened keywords
                ON LOWER(p.drug) LIKE '%' || dke.keyword || '%' -- Now a straightforward LIKE join
            WHERE
                -- Optimize by only considering prescriptions relevant to at least one time window
                (p.starttime >= DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND p.starttime <= fc.dischtime) -- Final 48h window
                OR
                (p.starttime >= fc.admittime AND p.starttime <= DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)) -- First 72h window
            GROUP BY
                fc.subject_id,
                fc.hadm_id,
                dke.drug_class
        )
SELECT
    pde.drug_class,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN pde.exposed_first_72h = 1 THEN pde.hadm_id END) * 100.0, nc.total_admissions) AS prevalence_first_72h_percent,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN pde.exposed_final_48h = 1 THEN pde.hadm_id END) * 100.0, nc.total_admissions) AS prevalence_final_48h_percent,
    (SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN pde.exposed_first_72h = 1 THEN pde.hadm_id END) * 100.0, nc.total_admissions)) -
    (SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN pde.exposed_final_48h = 1 THEN pde.hadm_id END) * 100.0, nc.total_admissions)) AS pp_difference
FROM
    patient_drug_exposure pde
CROSS JOIN
    num_cohort_admissions nc -- nc is a single row table, so CROSS JOIN is appropriate
GROUP BY
    pde.drug_class,
    nc.total_admissions
ORDER BY
    pde.drug_class;