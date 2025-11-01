WITH ami_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other' 
        END AS los_group,
        CASE 
            WHEN dx.seq_num = 1 THEN 'Primary'
            ELSE 'Secondary' 
        END AS ami_type
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON adm.hadm_id = dx.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 43 AND 53
        AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%')
),

procedure_counts AS (
    SELECT 
        aa.hadm_id,
        aa.los_group,
        aa.ami_type,
        COUNT(DISTINCT proc.icd_code) AS num_procedures
    FROM ami_admissions aa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON aa.hadm_id = proc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        (dicd.icd_code LIKE 'BW%' OR dicd.icd_code LIKE 'B02%')
        OR dicd.long_title LIKE '%radiograph%'
        OR dicd.long_title LIKE '%computed tomography%'
    GROUP BY aa.hadm_id, aa.los_group, aa.ami_type
)

SELECT 
    los_group,
    ami_type,
    APPROX_QUANTILES(num_procedures, 2)[OFFSET(1)] AS median_procedures,
    APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS q3
FROM procedure_counts
WHERE los_group IN ('1-3', '4-7')
GROUP BY los_group, ami_type
ORDER BY los_group, ami_type;