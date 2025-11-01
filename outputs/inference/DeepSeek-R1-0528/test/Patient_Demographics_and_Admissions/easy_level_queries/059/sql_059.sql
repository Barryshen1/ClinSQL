SELECT 
    a.hadm_id,
    MAX(i.los) AS max_icu_los
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
INNER JOIN (
    SELECT DISTINCT proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code 
        AND proc.icd_version = dicd.icd_version
    WHERE 
        UPPER(dicd.long_title) LIKE '%PERCUTANEOUS CORONARY INTERVENTION%'
        OR UPPER(dicd.long_title) LIKE '%PCI%'
) pci
    ON a.hadm_id = pci.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
GROUP BY a.hadm_id;