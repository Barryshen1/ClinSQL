WITH PCI_admissions AS (
    SELECT DISTINCT
        pi.subject_id,
        pi.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    -- Join with d_icd_procedures to get the long_title for ICD-10 description-based filtering
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
         ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
    WHERE
        -- ICD-9 codes commonly associated with PCI
        (pi.icd_version = 9 AND (
            pi.icd_code LIKE '36.0%' -- Percutaneous Transluminal Coronary Angioplasty (PTCA), e.g., 36.01, 36.02, 36.05
            OR pi.icd_code = '00.66' -- Insertion of drug-eluting coronary artery stent(s)
            OR pi.icd_code = '36.06' -- Insertion of non-drug-eluting coronary artery stent(s)
            OR pi.icd_code = '36.07' -- Insertion of coronary artery stent, unclassified type
        ))
        OR
        -- ICD-10 codes/descriptions commonly associated with PCI
        (pi.icd_version = 10 AND (
            pi.icd_code LIKE '027%' -- Codes like 0270, 0271, 0272, 0273, 0274 generally refer to Dilation of Coronary Artery, Percutaneous Approach
            -- More robust check using long_title for ICD-10 PCI definition
            OR (dp.long_title LIKE '%Coronary Artery%'
                AND dp.long_title LIKE '%Percutaneous Approach%'
                AND (dp.long_title LIKE '%Dilation%' OR dp.long_title LIKE '%Stent%'))
        ))
)
-- Main query to calculate the maximum ICU length of stay
SELECT
    MAX(icu.los) AS max_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
    AND icu.subject_id = adm.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
JOIN PCI_admissions pci
    ON adm.hadm_id = pci.hadm_id
    AND adm.subject_id = pci.subject_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69;