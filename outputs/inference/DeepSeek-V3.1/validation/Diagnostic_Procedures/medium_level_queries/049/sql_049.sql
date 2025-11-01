WITH sepsis_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize LOS
        CASE 
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 87 AND 97
        AND adm.hadm_id IN (
            -- Sepsis without shock
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE 
                (icd_code = '99591' AND icd_version = 9)   -- Sepsis
                OR (icd_code = '99592' AND icd_version = 9) -- Severe sepsis
                OR (icd_code = 'R6520' AND icd_version = 10) -- Sepsis without shock
            EXCEPT DISTINCT
            -- Exclude septic shock
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE 
                (icd_code = '78552' AND icd_version = 9)   -- Septic shock
                OR (icd_code = 'R6521' AND icd_version = 10) -- Severe sepsis with septic shock
        )
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
-- Count diagnostic procedures per admission
proc_counts AS (
    SELECT 
        sa.hadm_id,
        sa.los_group,
        COUNT(DISTINCT proc.icd_code) AS num_diagnostic_procedures
    FROM sepsis_admissions sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON sa.hadm_id = proc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE LOWER(dicd.long_title) LIKE '%diagnostic%'
    GROUP BY sa.hadm_id, sa.los_group
)
-- Compute mean procedures by LOS group
SELECT 
    los_group,
    COUNT(hadm_id) AS num_admissions,
    AVG(num_diagnostic_procedures) AS mean_diagnostic_procedures
FROM proc_counts
WHERE los_group IN ('1-3', '4-7')
GROUP BY los_group
ORDER BY los_group;