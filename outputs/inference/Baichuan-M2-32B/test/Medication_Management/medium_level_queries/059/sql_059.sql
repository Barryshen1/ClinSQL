WITH t2dm_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE icd_code IN (
        SELECT icd_code
        FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
        WHERE icd_version IN (9,10) 
            AND (long_title LIKE '%Type 2 diabetes mellitus%' 
                 OR long_title LIKE '%2nd diabetes mellitus%'
                 OR long_title LIKE '%Type II diabetes mellitus%')
    )
),
hf_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE icd_code IN (
        SELECT icd_code
        FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
        WHERE icd_version IN (9,10) 
            AND (long_title LIKE '%heart failure%' 
                 OR long_title LIKE '%congestive heart failure%'
                 OR long_title LIKE '%CHF%')
    )
),
cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        -- Using anchor_age for age group filtering (60-70 years)
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
        ON p.subject_id = a.subject_id
    INNER JOIN t2dm_diagnoses t2d 
        ON p.subject_id = t2d.subject_id AND a.hadm_id = t2d.hadm_id
    INNER JOIN hf_diagnoses hf 
        ON p.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 60 AND 70
        AND a.dischtime IS NOT NULL  -- ensure we have a discharge time for the final 24h
),
time_windows AS (
    SELECT 
        hadm_id,
        admittime,
        dischtime,
        DATETIME_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
        DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AS final_24h_start
    FROM cohort
),
drug_classes AS (
    SELECT 'antidiabetics' AS drug_class, 'insulin' AS keyword
    UNION ALL SELECT 'antidiabetics', 'metformin'
    UNION ALL SELECT 'antidiabetics', 'glipizide'
    UNION ALL SELECT 'antidiabetics', 'glyburide'
    UNION ALL SELECT 'antidiabetics', 'pioglitazone'
    UNION ALL SELECT 'antidiabetics', 'rosiglitazone'
    UNION ALL SELECT 'antidiabetics', 'sitagliptin'
    UNION ALL SELECT 'antidiabetics', 'linagliptin'
    UNION ALL SELECT 'antidiabetics', 'dapagliflozin'
    UNION ALL SELECT 'antidiabetics', 'empagliflozin'
    UNION ALL SELECT 'antidiabetics', 'canagliflozin'
    UNION ALL SELECT 'antidiabetics', 'semaglutide'
    UNION ALL SELECT 'antidiabetics', 'liraglutide'
    UNION ALL SELECT 'antidiabetics', 'exenatide'
    UNION ALL SELECT 'antidiabetics', 'glimepiride'
    UNION ALL SELECT 'antidiabetics', 'repaglinide'
    UNION ALL SELECT 'antidiabetics', 'acarbose'
    UNION ALL SELECT 'antidiabetics', 'miglitol'
    UNION ALL SELECT 'antidiabetics', 'troglitazone'
    UNION ALL SELECT 'antidiabetics', 'troxipide'
    UNION ALL SELECT 'antidiabetics', 'glucobay'
    UNION ALL SELECT 'antidiabetics', 'pramlintide'
    UNION ALL SELECT 'antidiabetics', 'exenatide'
    UNION ALL SELECT 'antidiabetics', 'liraglutide'
    UNION ALL SELECT 'antidiabetics', 'tirzepatide'
    UNION ALL
    SELECT 'beta_blockers', 'metoprolol'
    UNION ALL SELECT 'beta_blockers', 'carvedilol'
    UNION ALL SELECT 'beta_blockers', 'bisoprolol'
    UNION ALL SELECT 'beta_blockers', 'propranolol'
    UNION ALL SELECT 'beta_blockers', 'atenolol'
    UNION ALL SELECT 'beta_blockers', 'nadolol'
    UNION ALL SELECT 'beta_blockers', 'sotalol'
    UNION ALL SELECT 'beta_blockers', 'timolol'
    UNION ALL SELECT 'beta_blockers', 'pindolol'
    UNION ALL SELECT 'beta_blockers', 'acebutolol'
    UNION ALL SELECT 'beta_blockers', 'atenolol'
    UNION ALL SELECT 'beta_blockers', 'bucindolol'
    UNION ALL SELECT 'beta_blockers', 'carteolol'
    UNION ALL SELECT 'beta_blockers', 'esmolol'
    UNION ALL SELECT 'beta_blockers', 'indenolol'
    UNION ALL SELECT 'beta_blockers', 'labetalol'
    UNION ALL SELECT 'beta_blockers', 'metoprolol'
    UNION ALL SELECT 'beta_blockers', 'nadolol'
    UNION ALL SELECT 'beta_blockers', 'pindolol'
    UNION ALL SELECT 'beta_blockers', 'propranolol'
    UNION ALL SELECT 'beta_blockers', 'sotalol'
    UNION ALL SELECT 'beta_blockers', 'timolol'
    UNION ALL SELECT 'beta_blockers', 'xenonitroxylin'
    UNION ALL
    SELECT 'ACEi/ARB/ARNI', 'lisinopril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'enalapril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'ramipril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'perindopril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'quailapril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'trandolapril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'benazepril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'moexipril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'captopril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'fosinopril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'trandolapril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'lisinopril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'valsartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'losartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'irbesartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'candesartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'olmesartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'telmisartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'eprosartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'azilsartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'valsartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'sacubitril'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'valsartan'
    UNION ALL SELECT 'ACEi/ARB/ARNI', 'sacubitril/valsartan'
    UNION ALL
    SELECT 'loop_diuretics', 'furosemide'
    UNION ALL SELECT 'loop_diuretics', 'bumetanide'
    UNION ALL SELECT 'loop_diuretics', 'torsemide'
    UNION ALL SELECT 'loop_diuretics', 'ethacrynic'
),
prescriptions_with_class AS (
    SELECT DISTINCT ON (p.subject_id, p.hadm_id, p.drug) 
        p.*,
        dc.drug_class
    FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    INNER JOIN drug_classes dc 
        ON LOWER(p.drug) LIKE CONCAT('%', dc.keyword, '%')
    ORDER BY p.subject_id, p.hadm_id, p.drug, dc.drug_class
),
admissions_with_drug_initiations AS (
    SELECT 
        tw.hadm_id,
        dc.drug_class,
        MAX(CASE WHEN p.starttime BETWEEN tw.admittime AND tw.first_48h_end THEN 1 ELSE 0 END) AS initiated_first48,
        MAX(CASE WHEN p.starttime BETWEEN tw.final_24h_start AND tw.dischtime THEN 1 ELSE 0 END) AS initiated_final24
    FROM time_windows tw
    CROSS JOIN (SELECT DISTINCT drug_class FROM drug_classes) dc
    LEFT JOIN prescriptions_with_class p 
        ON tw.hadm_id = p.hadm_id 
        AND p.drug_class = dc.drug_class
    GROUP BY tw.hadm_id, dc.drug_class
),
final_results AS (
    SELECT 
        drug_class,
        COUNT(CASE WHEN initiated_first48 = 1 THEN 1 END) AS num_initiated_first48,
        COUNT(CASE WHEN initiated_final24 = 1 THEN 1 END) AS num_initiated_final24,
        COUNT(*) AS total_admissions,
        ROUND(COUNT(CASE WHEN initiated_first48 = 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS pct_first48,
        ROUND(COUNT(CASE WHEN initiated_final24 = 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS pct_final24,
        ROUND((COUNT(CASE WHEN initiated_final24 = 1 THEN 1 END) - COUNT(CASE WHEN initiated_first48 = 1 THEN 1 END)) * 100.0 / COUNT(*), 2) AS abs_diff_pp
    FROM admissions_with_drug_initiations
    GROUP BY drug_class
)
SELECT * FROM final_results
ORDER BY drug_class;