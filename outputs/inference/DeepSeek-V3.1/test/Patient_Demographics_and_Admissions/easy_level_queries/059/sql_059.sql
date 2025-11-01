WITH pci_patients AS (
    SELECT DISTINCT proc.subject_id, proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON proc.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 59 AND 69
        AND proc.icd_code LIKE '02[0-8]%'  -- Correct range for PCI procedures in ICD-10
)
SELECT i.hadm_id, MAX(i.los) AS max_icu_los
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN pci_patients pp
    ON i.subject_id = pp.subject_id AND i.hadm_id = pp.hadm_id
GROUP BY i.hadm_id
ORDER BY max_icu_los DESC;