WITH filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 82 AND 92
),
admissions_with_patients AS (
    SELECT a.hadm_id, a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN filtered_patients p ON a.subject_id = p.subject_id
),
cardiac_procedures AS (
    SELECT 
        p.hadm_id,
        COUNT(DISTINCT CASE WHEN d.icd_code IS NOT NULL THEN proc.icd_code END) AS distinct_cardiac_procedures
    FROM admissions_with_patients p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        ON p.hadm_id = proc.hadm_id AND p.subject_id = proc.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON proc.icd_code = d.icd_code AND proc.icd_version = d.icd_version
        AND REGEXP_CONTAINS(d.long_title, r'CARDIAC|HEART|CORONARY|PACEMAKER|DEFIBRILLATOR|VALVE|AORTIC|MITRAL|TRICUSPID|VENTRICULAR|ATRIAL|BYPASS|STENT|ANGIOPLASTY|CATHETERIZATION|ABLATION')
    GROUP BY p.hadm_id
)
SELECT 
    APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(25)] AS p25
FROM cardiac_procedures;