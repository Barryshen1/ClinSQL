WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 49 AND 59
),
admissions_with_diagnoses AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND dd.icd_code LIKE 'E11%'
    )
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND dd.icd_code LIKE 'I50%'
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
medication_mapping AS (
    SELECT 
        drug,
        CASE 
            WHEN drug LIKE '%insulin%' OR drug LIKE '%metformin%' OR drug LIKE '%glipizide%' OR drug LIKE '%glyburide%' OR drug LIKE '%pioglitazone%' THEN 'Antidiabetic'
            WHEN drug LIKE '%metoprolol%' OR drug LIKE '%carvedilol%' OR drug LIKE '%bisoprolol%' OR drug LIKE '%propranolol%' THEN 'Beta-Blocker'
            WHEN drug LIKE '%lisinopril%' OR drug LIKE '%losartan%' OR drug LIKE '%valsartan%' OR drug LIKE '%enalapril%' OR drug LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
            WHEN drug LIKE '%furosemide%' OR drug LIKE '%bumetanide%' OR drug LIKE '%torsemide%' THEN 'Loop Diuretic'
            ELSE NULL
        END AS class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY drug
    HAVING class IS NOT NULL
),
admission_meds AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        m.class,
        a.admittime AS first_24h_start,
        DATETIME_ADD(a.admittime, INTERVAL 24 HOUR) AS first_24h_end,
        DATETIME_SUB(a.dischtime, INTERVAL 48 HOUR) AS final_48h_start,
        a.dischtime AS final_48h_end,
        p.drug,
        p.starttime,
        p.stoptime
    FROM admissions_with_diagnoses a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
        ON a.hadm_id = p.hadm_id
    LEFT JOIN medication_mapping m ON p.drug = m.drug
),
class_status AS (
    SELECT 
        hadm_id,
        subject_id,
        class,
        MAX(CASE 
            WHEN starttime < first_24h_end 
                AND (stoptime IS NULL OR stoptime > first_24h_start) 
                THEN 1 
            ELSE 0 
        END) AS on_first_24h,
        MAX(CASE 
            WHEN starttime < final_48h_end 
                AND (stoptime IS NULL OR stoptime > final_48h_start) 
                THEN 1 
            ELSE 0 
        END) AS on_final_48h
    FROM admission_meds
    GROUP BY hadm_id, subject_id, class
),
final_output AS (
    SELECT 
        class,
        ROUND(100.0 * AVG(on_first_24h), 2) AS percent_on_first_24h,
        ROUND(100.0 * AVG(on_final_48h), 2) AS percent_on_final_48h,
        SUM(CASE WHEN on_first_24h = 1 AND on_final_48h = 1 THEN 1 ELSE 0 END) AS count_continued,
        SUM(CASE WHEN on_first_24h = 0 AND on_final_48h = 1 THEN 1 ELSE 0 END) AS count_initiated,
        SUM(CASE WHEN on_first_24h = 1 AND on_final_48h = 0 THEN 1 ELSE 0 END) AS count_discontinued
    FROM class_status
    GROUP BY class
)
SELECT * FROM final_output;