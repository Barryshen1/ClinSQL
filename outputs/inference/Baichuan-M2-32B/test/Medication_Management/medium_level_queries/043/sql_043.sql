WITH eligible_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code
                AND d.icd_version = dd.icd_version
            WHERE
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND (dd.long_title LIKE '%diabetes%' OR dd.icd_code LIKE 'E1%')
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code
                AND d.icd_version = dd.icd_version
            WHERE
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND (dd.long_title LIKE '%heart failure%' OR dd.icd_code LIKE 'I50.%')
        )
        AND a.dischtime IS NOT NULL
        AND (a.dischtime - a.admittime) >= INTERVAL 48 HOUR
),
drug_categories AS (
    SELECT
        subject_id,
        hadm_id,
        drug,
        starttime,  -- Added to fix the error
        CASE
            WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%dapagliflozin%' THEN 'Antidiabetics'
            WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%' OR LOWER(drug) LIKE '%bisoprolol%' OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%propranolol%' THEN 'Beta-blockers'
            WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%candesartan%' OR LOWER(drug) LIKE '%enalapril%' OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
            WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' OR LOWER(drug) LIKE '%torsemide%' THEN 'Loop diuretics'
            ELSE NULL
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
),
first_prescription_per_class AS (
    SELECT
        subject_id,
        hadm_id,
        drug_class,
        starttime,
        ROW_NUMBER() OVER (
            PARTITION BY subject_id, hadm_id, drug_class
            ORDER BY starttime
        ) AS rn
    FROM drug_categories
    WHERE drug_class IS NOT NULL
),
initiations AS (
    SELECT
        fp.subject_id,
        fp.hadm_id,
        fp.drug_class,
        fp.starttime,
        ea.admittime,
        ea.dischtime,
        CASE WHEN fp.starttime BETWEEN ea.admittime AND (ea.admittime + INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS in_first48h,
        CASE WHEN fp.starttime BETWEEN (ea.dischtime - INTERVAL 12 HOUR) AND ea.dischtime THEN 1 ELSE 0 END AS in_last12h
    FROM first_prescription_per_class fp
    INNER JOIN eligible_admissions ea
        ON fp.subject_id = ea.subject_id
        AND fp.hadm_id = ea.hadm_id
    WHERE fp.rn = 1
),
aggregated AS (
    SELECT
        drug_class,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        SUM(in_first48h) AS initiated_first48h,
        SUM(in_last12h) AS initiated_last12h
    FROM initiations
    GROUP BY drug_class
),
rates AS (
    SELECT
        drug_class,
        (SUM(initiated_first48h) * 100.0 / total_admissions) AS rate_first48h,
        (SUM(initiated_last12h) * 100.0 / total_admissions) AS rate_last12h,
        (SUM(initiated_last12h) * 100.0 / total_admissions) - (SUM(initiated_first48h) * 100.0 / total_admissions) AS net_change
    FROM aggregated
    GROUP BY drug_class
)
SELECT
    drug_class,
    ROUND(rate_first48h, 1) AS rate_first48h,
    ROUND(rate_last12h, 1) AS rate_last12h,
    ROUND(net_change, 1) AS net_change
FROM rates
ORDER BY drug_class;