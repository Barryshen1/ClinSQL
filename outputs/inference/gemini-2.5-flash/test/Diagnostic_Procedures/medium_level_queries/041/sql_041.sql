WITH BaseCohort AS (
    -- Select primary patient and admission data for males aged 51-61
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        pa.anchor_age,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 51 AND 61
),
PancreatitisAdmissions AS (
    -- Identify admissions with acute pancreatitis diagnosis and determine if it's primary or secondary
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.los_days,
        -- Check if acute pancreatitis is the primary diagnosis (seq_num = 1)
        MAX(CASE WHEN di.seq_num = 1 AND LOWER(d_icd.long_title) LIKE '%acute pancreatitis%' THEN 1 ELSE 0 END) AS is_primary_acute_pancreatitis_diag,
        -- This flag is just to ensure the admission actually has an acute pancreatitis diagnosis
        MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%acute pancreatitis%' THEN 1 ELSE 0 END) AS has_acute_pancreatitis_diag
    FROM
        BaseCohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
        ON bc.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses AS d_icd
        ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
    GROUP BY
        bc.subject_id, bc.hadm_id, bc.los_days
    HAVING
        MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%acute pancreatitis%' THEN 1 ELSE 0 END) = 1 -- Ensure at least one acute pancreatitis diagnosis
),
CategorizedPancreatitisCohort AS (
    -- Assign LOS and diagnosis categories based on the requirements
    SELECT
        p_adm.subject_id,
        p_adm.hadm_id,
        CASE
            WHEN p_adm.is_primary_acute_pancreatitis_diag = 1 THEN 'Primary Pancreatitis'
            ELSE 'Secondary Pancreatitis'
        END AS diagnosis_category,
        CASE
            WHEN p_adm.los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 Days'
            WHEN p_adm.los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 Days'
            ELSE NULL -- Filter out other LOS ranges initially
        END AS los_category
    FROM PancreatitisAdmissions AS p_adm
    WHERE
        p_adm.los_days BETWEEN 1 AND 7 -- Filter to only required LOS ranges
),
RadiographyCTCounts AS (
    -- Count radiography/CT procedures for each admission
    SELECT
        proc.hadm_id,
        COUNT(proc.icd_code) AS num_radiography_cts
    FROM
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd AS proc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
        LOWER(d_proc.long_title) LIKE '%radiograph%'
        OR LOWER(d_proc.long_title) LIKE '%x-ray%'
        OR LOWER(d_proc.long_title) LIKE '%computed tomography%'
        OR LOWER(d_proc.long_title) LIKE '%ct scan%'
    GROUP BY
        proc.hadm_id
)
-- Final aggregation to produce patient counts and mean radiography/CTs
SELECT
    cpc.los_category,
    cpc.diagnosis_category,
    COUNT(DISTINCT cpc.subject_id) AS patient_count,
    ROUND(AVG(COALESCE(rct.num_radiography_cts, 0)), 2) AS mean_radiography_cts_per_admission
FROM
    CategorizedPancreatitisCohort AS cpc
LEFT JOIN
    RadiographyCTCounts AS rct
    ON cpc.hadm_id = rct.hadm_id
GROUP BY
    cpc.los_category,
    cpc.diagnosis_category
ORDER BY
    cpc.los_category,
    cpc.diagnosis_category;