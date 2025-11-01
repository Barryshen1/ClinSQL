WITH heart_failure_males AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE p.gender = 'M'
    AND LOWER(d.long_title) LIKE '%heart failure%'
),
hemoglobin_nadir AS (
    SELECT 
        le.hadm_id,
        MIN(le.valuenum) AS nadir_hemoglobin
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
    WHERE (LOWER(li.label) LIKE '%hemoglobin%' OR LOWER(li.label) LIKE '%hgb%')
    AND le.hadm_id IN (SELECT hadm_id FROM heart_failure_males)
    GROUP BY le.hadm_id
)
SELECT 
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY nadir_hemoglobin) AS percentile_75
FROM hemoglobin_nadir;